import SwiftUI

struct NetWorthView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore

    @State private var selectedRange: NetWorthTimeRange = .oneYear

    private var chartPoints: [NetWorthChartPoint] {
        netWorth.chartPoints(range: selectedRange)
    }

    private var accountGroups: [NetWorthAccountGroup] {
        NetWorthHistoryEngine.accountGroups(from: transactions.accounts)
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
                            if let linked = transactions.account(for: account.id) {
                                NavigationLink {
                                    AccountDetailView(account: linked)
                                } label: {
                                    NetWorthAccountRowLabel(
                                        name: account.name,
                                        balance: displayBalance(account.balance, groupTitle: group.title)
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
            } else if !transactions.bankConnections.isEmpty || !transactions.transactions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Accounts loading",
                        systemImage: "building.columns",
                        description: Text("Pull down to refresh balances and account list.")
                    )
                }
                .listRowBackground(Color.clear)
            }

            Section("Today") {
                LabeledContent("Assets", value: FinanceFormatting.currency(netWorth.currentAssets))
                LabeledContent("Liabilities", value: FinanceFormatting.currency(netWorth.currentLiabilities))
                LabeledContent("Net worth", value: FinanceFormatting.currency(netWorth.currentNetWorth))
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
            Button("Refresh snapshot") {
                Task { await captureSnapshot() }
            }
        }
        .refreshable {
            await reload()
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.loadAll(client: client)
        await transactions.refreshPlaidAccountsIfNeeded(
            client: client,
            userId: auth.userId
        )
        await accountBalances.reload(client: client)
        await netWorth.reload(
            client: client,
            accounts: transactions.accounts,
            accountSnapshots: accountBalances.snapshots,
            transactions: transactions.transactions
        )
        await netWorth.recordDailySnapshotIfNeeded(
            client: client,
            accounts: transactions.accounts,
            accountBalances: accountBalances
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
