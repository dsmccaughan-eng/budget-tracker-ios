import SwiftUI

struct NetWorthGroupDetailView: View {
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var investments: InvestmentStore

    let kind: NetWorthAccountGroupKind

    @State private var selectedRange: NetWorthTimeRange = .oneYear

    private var displayAccounts: [Account] {
        if !transactions.accounts.isEmpty {
            return transactions.accounts
        }
        return netWorth.cachedAccounts
    }

    private var groupAccounts: [Account] {
        displayAccounts.filter { kind.matches(accountType: $0.type) }
    }

    private var chartPoints: [NetWorthChartPoint] {
        NetWorthHistoryEngine.groupChartPoints(
            kind: kind,
            accounts: groupAccounts,
            accountSnapshots: accountBalances.snapshots,
            transactions: transactions.transactions,
            investmentTransactions: investments.transactions,
            range: selectedRange
        )
    }

    private var groupTotal: Double {
        NetWorthHistoryEngine.accountGroups(from: groupAccounts)
            .first { $0.kind == kind }?
            .total ?? (chartPoints.last?.netWorth ?? 0)
    }

    var body: some View {
        List {
            Section {
                NetWorthChartView(
                    points: chartPoints,
                    selectedRange: $selectedRange,
                    title: kind.chartTitle,
                    allowsMonthlyGranularity: true
                )
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Today") {
                LabeledContent(kind.title, value: FinanceFormatting.currency(groupTotal))
                LabeledContent("Accounts", value: "\(groupAccounts.count)")
            }

            if !groupAccounts.isEmpty {
                Section("Accounts") {
                    ForEach(groupAccounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            HStack {
                                Text(FinanceFormatting.accountLabel(account))
                                Spacer()
                                Text(FinanceFormatting.currency(
                                    AccountBalanceHistoryEngine.displayBalance(
                                        account.currentBalance ?? 0,
                                        accountType: account.type
                                    )
                                ))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
