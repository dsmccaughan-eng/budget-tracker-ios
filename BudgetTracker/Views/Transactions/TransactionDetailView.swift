import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var merchantRules: MerchantRulesStore

    let transaction: Transaction
    @State private var selectedCategory: String
    @State private var saveMerchantRule = true
    @State private var isSaving = false
    @State private var showSavedConfirmation = false

    init(transaction: Transaction) {
        self.transaction = transaction
        _selectedCategory = State(initialValue: transaction.category)
    }

    private var categorySource: CategorySource? {
        CategorySource.from(transaction.categorySource)
    }

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Merchant", value: FinanceFormatting.displayName(for: transaction))
                LabeledContent("Amount", value: TransactionFormatting.formattedAmount(transaction.amount))
                LabeledContent("Type", value: TransactionFormatting.amountLabel(transaction.amount))
                LabeledContent("Date", value: transaction.date)
                if let subcategory = transaction.subcategory, !subcategory.isEmpty {
                    LabeledContent("Subcategory", value: subcategory)
                }
                LabeledContent("Status", value: transaction.pending ? "Pending" : "Posted")
            }

            if let categorySource {
                Section("Category source") {
                    CategorySourceBadge(source: categorySource)
                    if let message = categorySource.confirmationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(BudgetCategories.all, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .disabled(isSaving)

                Toggle(
                    "Remember for future purchases from this merchant",
                    isOn: $saveMerchantRule
                )
                .font(.subheadline)

                Button(isSaving ? "Saving…" : "Save category") {
                    Task { await saveCategory() }
                }
                .disabled(isSaving || (selectedCategory == transaction.category && !saveMerchantRule))

                NavigationLink("Merchant rule library (\(merchantRules.rules.count))") {
                    CategoryRulesView()
                }

                NavigationLink("Split transaction") {
                    SplitTransactionView(transaction: transaction)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Category saved", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            if saveMerchantRule {
                Text("Future transactions matching “\(FinanceFormatting.displayName(for: transaction))” will use \(selectedCategory).")
            } else {
                Text("Only this transaction was updated.")
            }
        }
        .task {
            guard let client = auth.activeSupabaseClient else { return }
            if merchantRules.rules.isEmpty {
                await merchantRules.reload(client: client)
            }
        }
    }

    private func saveCategory() async {
        guard let client = auth.activeSupabaseClient else { return }
        isSaving = true
        defer { isSaving = false }
        await transactions.updateCategory(
            transaction: transaction,
            category: selectedCategory,
            saveMerchantRule: saveMerchantRule,
            merchantRules: merchantRules,
            client: client
        )
        if transactions.errorMessage == nil {
            showSavedConfirmation = true
        }
    }
}
