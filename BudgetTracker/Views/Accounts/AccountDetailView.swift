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
        isInvestmentAccount && (!investmentTransactions.isEmpty || hasCashActivity)
    }

    private var hasCashActivity: Bool {
        transactions.transactions.contains { $0.accountId == accountId && !$0.pending }
    }

    private var usesSnapshotHistory: Bool {
        isInvestmentAccount && !usesActivityHistory
    }

    var body: some View {
        List {
            Section {
                AccountBalanceChartView(
                    accountLabel: FinanceFormatting.accountLabel(account),
                    points: historyPoints,
                    selectedRange: $selectedRange,
                    usesSnapshotHistory: usesSnapshotHistory,
                    allowsMonthlyGranularity: true
                )
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Today") {
                if let balance = displayBalance {
                    LabeledContent("Current balance", value: FinanceFormatting.currency(
                        AccountBalanceHistoryEngine.displayBalance(balance, accountType: account.type)
                    ))
                }
                if let available = account.availableBalance {
                    LabeledContent("Available", value: FinanceFormatting.currency(available))
                }
                LabeledContent("Type", value: account.type.capitalized)
                if let holdingsTotal = investments.holdingsMarketValue(for: accountId),
                   let plaid = account.currentBalance,
                   holdingsTotal > plaid + 1 {
                    Text("Balance uses holdings market value (\(FinanceFormatting.currency(holdingsTotal))); bank feed reported \(FinanceFormatting.currency(plaid)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isInvestmentAccount {
                investmentHoldingsSection
                investmentActivitySection
            }

            if let error = investments.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            } else if let summary = investments.lastSyncSummary {
                Section {
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
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
                Text("No holdings yet. Pull to refresh to sync from Plaid. If this bank was linked before Investments was enabled, reconnect it from Accounts → Enable holdings.")
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
            Button("Sync holdings now") {
                Task { await reloadFromServer() }
            }
            .buttonStyle(.bordered)
            .disabled(investments.isSyncing)
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

    private var displayBalance: Double? {
        if isInvestmentAccount {
            return investments.preferredBalance(for: account)
        }
        return account.currentBalance
    }

    private var historyTaskID: String {
        let balanceKey = account.currentBalance.map { String($0) } ?? "nil"
        let cashCount = transactions.transactions.filter { $0.accountId == accountId }.count
        return "\(accountId.uuidString)-\(selectedRange.rawValue)-\(balanceKey)-\(accountBalances.snapshots.count)-\(investmentTransactions.count)-\(cashCount)-\(investments.holdings.count)"
    }

    private var historyExplanation: String {
        if isInvestmentAccount {
            return "Total value is an accumulation curve: contributions, withdrawals, and transfers are added on their dates, market gains or losses are filled in from saved snapshots, and today is pinned to the live balance. Buys and sells inside the account are ignored."
        }
        return "Balances are estimated day-by-day from your synced transactions and current balance. Saved snapshots from account refreshes replace estimates when available."
    }

    private func rebuildHistoryPoints() {
        if isInvestmentAccount {
            var chartAccount = account
            if let preferred = investments.preferredBalance(for: account) {
                chartAccount.currentBalance = preferred
            }
            historyPoints = InvestmentHistoryEngine.chartPoints(
                account: chartAccount,
                snapshots: accountBalances.snapshots,
                transactions: investmentTransactions,
                cashTransactions: transactions.transactions,
                investmentAccounts: transactions.accounts.filter {
                    !AccountBalanceHistoryEngine.supportsTransactionReconstruction(accountType: $0.type)
                },
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
        if investments.holdings.isEmpty || investmentTransactions.isEmpty {
            await investments.loadAll(client: client)
        }
    }

    private func reloadFromServer() async {
        guard let client = auth.activeSupabaseClient else { return }
        if isInvestmentAccount {
            // Holdings sync writes corrected balances. Do not call /accounts/get afterward —
            // retirement providers often return a stale balance that overwrites the fix.
            await investments.syncFromPlaid(client: client)
            await transactions.loadAll(client: client, showsLoading: false)
        } else {
            await transactions.refreshAccountsFromPlaid(
                client: client,
                userId: auth.userId,
                showsLoading: true
            )
        }
        await accountBalances.reload(client: client)
        var liveAccount = transactions.account(for: accountId) ?? account
        if isInvestmentAccount, let preferred = investments.preferredBalance(for: liveAccount) {
            liveAccount.currentBalance = preferred
        }
        await accountBalances.recordTodaySnapshots(accounts: [liveAccount], client: client)
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
