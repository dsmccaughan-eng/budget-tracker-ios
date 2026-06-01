import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore

    let transaction: Transaction
    @State private var selectedCategory: String
    @State private var isSaving = false

    init(transaction: Transaction) {
        self.transaction = transaction
        _selectedCategory = State(initialValue: transaction.category)
    }

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Merchant", value: FinanceFormatting.displayName(for: transaction))
                LabeledContent("Amount", value: FinanceFormatting.currency(abs(transaction.amount)))
                LabeledContent("Date", value: transaction.date)
                if let subcategory = transaction.subcategory, !subcategory.isEmpty {
                    LabeledContent("Subcategory", value: subcategory)
                }
                LabeledContent("Status", value: transaction.pending ? "Pending" : "Posted")
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(BudgetCategories.all, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .disabled(isSaving)

                Button(isSaving ? "Saving…" : "Save category") {
                    Task { await saveCategory() }
                }
                .disabled(isSaving || selectedCategory == transaction.category)

                NavigationLink("Split transaction") {
                    SplitTransactionView(transaction: transaction)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveCategory() async {
        isSaving = true
        defer { isSaving = false }
        await transactions.updateCategory(
            transaction: transaction,
            category: selectedCategory,
            client: auth.supabaseClient
        )
    }
}
