import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore
    @EnvironmentObject private var investments: InvestmentStore

    private let accountId: UUID
    private let fallbackAccount: Account

    @State private var selectedRange: NetWorthTimeRange = .oneYear
    @State private var historyPoints: [AccountBalancePoint] = []

    init(account: Account) {
        accountId = account.id
        fallbackAccount = account
    }

    private var account: Account {
        transactions.account(for: accountId) ?? fallbackAccount
    }

    private var isInvestmentAccount: Bool {
        !AccountBalanceHistoryEngine.supportsTransactionReconstruction(accountType: account.type)
    }

    private var investmentTransactions: [InvestmentTransaction] {
        investments.transactions(for: accountId)
    }

    private var usesActivityHistory: Bool {
        isInvestmentAccount && !investmentTransactions.isEmpty
    }

    private var usesSnapshotHistory: Bool {
        !usesActivityHistory && isInvestmentAccount
    }

    var body: some View {
        List {
            Section {
                AccountBalanceChartView(
                    accountLabel: FinanceFormatting.accountLabel(account),
                    points: historyPoints,
                    selectedRange: $selectedRange,
                    usesSnapshotHistory: usesSnapshotHistory
                )
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Today") {
                if let balance = account.currentBalance {
                    LabeledContent("Current balance", value: FinanceFormatting.currency(
                        AccountBalanceHistoryEngine.displayBalance(balance, accountType: account.type)
                    ))
                }
                if let available = account.availableBalance {
                    LabeledContent("Available", value: FinanceFormatting.currency(available))
                }
                LabeledContent("Type", value: account.type.capitalized)
            }

            if isInvestmentAccount {
                investmentHoldingsSection
                investmentActivitySection
            }

            Section("How this works") {
                Text(historyExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await reloadFromServer()
        }
        .task(id: historyTaskID) {
            await ensureInvestmentDataLoaded()
            rebuildHistoryPoints()
        }
    }

    @ViewBuilder
    private var investmentHoldingsSection: some View {
        Section("Holdings") {
            let accountHoldings = investments.holdings(for: accountId)
            let lookup = investments.securitiesByID()

            if investments.isSyncing {
                ProgressView("Syncing holdings…")
            } else if accountHoldings.isEmpty {
                Text("No holdings yet. Pull to refresh after your bank supports Plaid Investments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountHoldings.sorted(by: { ($0.institutionValue ?? 0) > ($1.institutionValue ?? 0) })) { holding in
                    let security = investments.security(for: holding, lookup: lookup)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(security?.tickerSymbol ?? security?.name ?? holding.plaidSecurityId)
                            .font(.headline)
                        if let name = security?.name, security?.tickerSymbol != nil {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("\(holding.quantity.formatted(.number.precision(.fractionLength(0...4)))) shares")
                            Spacer()
                            if let value = holding.institutionValue {
                                Text(FinanceFormatting.currency(value))
                                    .fontWeight(.semibold)
                            }
                        }
                        .font(.subheadline)
                        if let price = holding.institutionPrice {
                            Text("Price \(FinanceFormatting.currency(price))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var investmentActivitySection: some View {
        Section("Recent activity") {
            if investmentTransactions.isEmpty {
                Text("Investment transactions sync separately from everyday spending.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(investmentTransactions.prefix(25))) { txn in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(txn.name)
                                .font(.headline)
                            Spacer()
                            Text(FinanceFormatting.currency(txn.amount))
                                .foregroundStyle(txn.amount >= 0 ? .primary : Color.green)
                        }
                        HStack {
                            Text(Self.shortDate(txn.date))
                            if let subtype = txn.subtype ?? txn.type {
                                Text("·")
                                Text(subtype.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            if let quantity = txn.quantity, abs(quantity) > 0.0001 {
                                Spacer()
                                Text("\(quantity.formatted(.number.precision(.fractionLength(0...4)))) sh")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var historyTaskID: String {
        let balanceKey = account.currentBalance.map { String($0) } ?? "nil"
        return "\(accountId.uuidString)-\(selectedRange.rawValue)-\(balanceKey)-\(accountBalances.snapshots.count)-\(investmentTransactions.count)-\(investments.holdings.count)"
    }

    private var historyExplanation: String {
        if usesActivityHistory {
            return "History combines synced investment activity with saved daily balance snapshots. Market moves between activity days may not appear until you refresh accounts."
        }
        if isInvestmentAccount {
            return "Investment balances change with the market. History comes from saved daily balance snapshots when you refresh accounts on Net Worth. Sync investment activity for richer history."
        }
        return "Balances are estimated day-by-day from your synced transactions and current balance. Saved snapshots from account refreshes replace estimates when available."
    }

    private func rebuildHistoryPoints() {
        if usesActivityHistory {
            historyPoints = InvestmentHistoryEngine.chartPoints(
                account: account,
                snapshots: accountBalances.snapshots,
                transactions: investmentTransactions,
                range: selectedRange
            ).map { point in
                AccountBalancePoint(
                    date: point.date,
                    dateString: point.dateString,
                    balance: AccountBalanceHistoryEngine.displayBalance(point.balance, accountType: account.type),
                    source: point.source
                )
            }
            return
        }

        historyPoints = AccountBalanceHistoryEngine.historyPoints(
            account: account,
            snapshots: accountBalances.snapshots,
            transactions: transactions.transactions,
            range: selectedRange
        )
    }

    private func ensureInvestmentDataLoaded() async {
        guard isInvestmentAccount, let client = auth.activeSupabaseClient else { return }
        if investments.holdings.isEmpty && investmentTransactions.isEmpty {
            await investments.loadAll(client: client)
        }
    }

    private func reloadFromServer() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.refreshAccountsFromPlaid(
            client: client,
            userId: auth.userId,
            showsLoading: true
        )
        if isInvestmentAccount {
            await investments.syncFromPlaid(client: client)
        }
        await accountBalances.reload(client: client)
        await accountBalances.recordTodaySnapshots(accounts: [account], client: client)
        rebuildHistoryPoints()
    }

    private static func shortDate(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
