import SwiftUI

struct CategoryTransactionsView: View {
    @EnvironmentObject private var transactions: TransactionStore

    let category: String
    let referenceMonth: Date

    private var monthTransactions: [Transaction] {
        BudgetMath.transactionsForCategory(
            transactions: transactions.transactions,
            category: category,
            referenceDate: referenceMonth
        )
    }

    private var netSpent: Double {
        monthTransactions.reduce(0) { $0 + $1.amount }
    }

    private var title: String {
        let selected = BudgetMath.startOfMonth(referenceMonth)
        let current = BudgetMath.startOfMonth(Date())
        if selected == current {
            return "\(category) this month"
        }
        return "\(category) · \(selected.formatted(.dateTime.month(.wide).year()))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(monthTransactions.count)")
                LabeledContent("Net spending", value: FinanceFormatting.currency(netSpent))
            }

            if monthTransactions.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "tray",
                    description: Text("Nothing in \(category) for this month.")
                )
            } else {
                Section("Transactions") {
                    ForEach(monthTransactions) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRowView(
                                transaction: transaction,
                                account: transactions.account(for: transaction.accountId)
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
