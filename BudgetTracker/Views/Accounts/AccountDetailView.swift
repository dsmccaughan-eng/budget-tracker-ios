import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore

    let account: Account

    @State private var selectedRange: NetWorthTimeRange = .oneYear

    private var historyPoints: [AccountBalancePoint] {
        AccountBalanceHistoryEngine.historyPoints(
            account: account,
            snapshots: accountBalances.snapshots,
            transactions: transactions.transactions,
            range: selectedRange
        )
    }

    var body: some View {
        List {
            Section {
                AccountBalanceChartView(
                    accountLabel: FinanceFormatting.accountLabel(account),
                    points: historyPoints,
                    selectedRange: $selectedRange
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

            Section("How this works") {
                Text("Balances are estimated day-by-day from your synced transactions and current balance. Saved snapshots from account refreshes replace estimates when available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
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
        await accountBalances.reload(client: client)
        await accountBalances.recordTodaySnapshots(accounts: [account], client: client)
    }
}
