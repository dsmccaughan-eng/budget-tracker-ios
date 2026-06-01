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
                Section("Accounts") {
                    ForEach(accountGroups) { group in
                        NetWorthAccountGroupSection(group: group)
                    }
                }
            }

            Section("Today") {
                LabeledContent("Assets", value: FinanceFormatting.currency(netWorth.currentAssets))
                LabeledContent("Liabilities", value: FinanceFormatting.currency(netWorth.currentLiabilities))
                LabeledContent("Net worth", value: FinanceFormatting.currency(netWorth.currentNetWorth))
            }

            Section("History") {
                Text("Past year uses daily account balances from synced transactions and recorded snapshots. Today’s total is saved automatically once per day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if netWorth.snapshots.isEmpty {
                    Text("Daily snapshots will appear after your next app open with linked accounts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(netWorth.snapshots.prefix(14)) { snap in
                        HStack {
                            Text(snap.date)
                            Spacer()
                            Text(FinanceFormatting.currency(snap.netWorth))
                                .foregroundStyle(.secondary)
                        }
                    }
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
            await reloadIfNeeded()
        }
    }

    private func reloadIfNeeded() async {
        guard let client = auth.activeSupabaseClient else { return }
        if netWorth.snapshots.isEmpty {
            await reload()
        }
    }

    private func reload() async {
        guard let client = auth.activeSupabaseClient else { return }
        if transactions.accounts.isEmpty {
            await transactions.loadAll(client: client)
        }
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
}

private struct NetWorthAccountGroupSection: View {
    @EnvironmentObject private var transactions: TransactionStore
    let group: NetWorthAccountGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(FinanceFormatting.currency(group.total))
                    .font(.subheadline.weight(.bold))
            }
            .padding(.vertical, 10)

            ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                NavigationLink {
                    if let linked = linkedAccount(account) {
                        AccountDetailView(account: linked)
                    }
                } label: {
                    HStack {
                        Text(account.name)
                            .font(.subheadline)
                        Spacer()
                        Text(FinanceFormatting.currency(displayBalance(account.balance)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 8)
                    .background(index.isMultiple(of: 2) ? Color(.systemGray6).opacity(0.5) : Color.clear)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func displayBalance(_ balance: Double) -> Double {
        group.title == "Loan" ? -abs(balance) : balance
    }

    private func linkedAccount(_ row: NetWorthAccountRow) -> Account? {
        transactions.accounts.first { $0.id == row.id }
    }
}
