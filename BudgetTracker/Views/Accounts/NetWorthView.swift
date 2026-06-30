import SwiftUI
import Supabase

struct NetWorthView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore
    @EnvironmentObject private var investments: InvestmentStore

    @State private var selectedRange: NetWorthTimeRange = .oneYear

    private var chartPoints: [NetWorthChartPoint] {
        netWorth.chartPoints(range: selectedRange)
    }

    private var accountsByID: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: transactions.accounts.map { ($0.id, $0) })
    }

    private var displayAccounts: [Account] {
        if !transactions.accounts.isEmpty {
            return transactions.accounts
        }
        return netWorth.cachedAccounts
    }

    private var accountGroups: [NetWorthAccountGroup] {
        NetWorthHistoryEngine.accountGroups(from: displayAccounts)
    }

    var body: some View {
        List {
            Section {
                NetWorthChartView(points: chartPoints, selectedRange: $selectedRange)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)

            if !accountGroups.isEmpty {
                ForEach(accountGroups) { group in
                    Section {
                        ForEach(group.accounts) { account in
                            if let linked = accountsByID[account.id] {
                                NavigationLink {
                                    AccountDetailView(account: linked)
                                } label: {
                                    NetWorthAccountRowLabel(
                                        name: account.name,
                                        balance: displayBalance(
                                            linked.currentBalance ?? account.balance,
                                            groupTitle: group.title
                                        )
                                    )
                                }
                                .listRowInsets(Self.accountRowInsets)
                            } else {
                                NetWorthAccountRowLabel(
                                    name: account.name,
                                    balance: displayBalance(account.balance, groupTitle: group.title)
                                )
                                .listRowInsets(Self.accountRowInsets)
                            }
                        }
                    } header: {
                        NetWorthAccountGroupHeader(title: group.title, total: group.total)
                    }
                }
            } else if needsAccountRecovery {
                Section {
                    ContentUnavailableView(
                        "Accounts not loaded",
                        systemImage: "building.columns",
                        description: Text(recoveryMessage)
                    )
                    Button("Refresh net worth") {
                        Task { await refreshFromPlaid() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            if let loadError = transactions.errorMessage, displayAccounts.isEmpty {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                LabeledContent("Assets", value: FinanceFormatting.currency(netWorth.currentAssets))
                LabeledContent("Liabilities", value: FinanceFormatting.currency(netWorth.currentLiabilities))
                LabeledContent("Net worth", value: FinanceFormatting.currency(netWorth.currentNetWorth))
            } header: {
                Text("Today")
            } footer: {
                Text("Balances refresh automatically once per day when you open the app. Tap ↻ or pull down for the latest from your bank.")
            }

            if let error = netWorth.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Net Worth")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refreshFromPlaid() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh net worth")
                .disabled(transactions.isLoading)

                Button("Snapshot") {
                    Task { await captureSnapshot() }
                }
            }
        }
        .refreshable {
            await refreshFromPlaid()
        }
    }

    private var needsAccountRecovery: Bool {
        !transactions.bankConnections.isEmpty || !transactions.transactions.isEmpty
    }

    private var recoveryMessage: String {
        if !transactions.bankConnections.isEmpty {
            return "Your bank is connected but account balances haven't loaded yet. Tap refresh or pull down."
        }
        return "Transactions are synced but account rows are missing. Tap refresh or pull down."
    }

    private func refreshFromPlaid() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.refreshAccountsFromPlaid(
            client: client,
            userId: auth.userId,
            showsLoading: true
        )
        await transactions.refreshAccountsIfMissing(
            client: client,
            userId: auth.userId
        )
        await reloadNetWorthFromStore(client: client)
        await investments.loadAll(client: client)
        await netWorth.recordDailySnapshotIfNeeded(
            client: client,
            accounts: transactions.accounts,
            accountBalances: accountBalances
        )
    }

    private func reloadNetWorthFromStore(client: SupabaseClient) async {
        await accountBalances.reload(client: client)
        await netWorth.reload(
            client: client,
            accounts: transactions.accounts,
            accountSnapshots: accountBalances.snapshots,
            transactions: transactions.transactions
        )
    }

    private func captureSnapshot() async {
        guard let client = auth.activeSupabaseClient else { return }
        await netWorth.captureSnapshot(
            client: client,
            accounts: transactions.accounts,
            accountBalances: accountBalances
        )
    }

    private func displayBalance(_ balance: Double, groupTitle: String) -> Double {
        groupTitle == "Loan" ? -abs(balance) : balance
    }

    private static let accountRowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
}

private struct NetWorthAccountGroupHeader: View {
    let title: String
    let total: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(FinanceFormatting.currency(total))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .textCase(nil)
    }
}

private struct NetWorthAccountRowLabel: View {
    let name: String
    let balance: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(FinanceFormatting.currency(balance))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}
