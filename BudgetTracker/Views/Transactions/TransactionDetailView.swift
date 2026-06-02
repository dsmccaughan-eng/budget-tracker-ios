import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var merchantRules: MerchantRulesStore

    let transaction: Transaction
    @State private var selectedCategory: String
    @State private var saveMerchantRule = true
    @State private var isFixedBill: Bool
    @State private var billNickname: String
    @State private var billDueDay: Int
    @State private var billAmount: Double
    @State private var isSavingCategory = false
    @State private var isSavingBill = false
    @State private var excludedFromBudget = false
    @State private var showSavedConfirmation = false
    @State private var showBillSavedConfirmation = false

    init(transaction: Transaction) {
        self.transaction = transaction
        _selectedCategory = State(initialValue: transaction.category)
        _isFixedBill = State(initialValue: transaction.isFixedBill)
        _billNickname = State(initialValue: BillsEngine.displayName(for: transaction))
        _billDueDay = State(initialValue: transaction.billDueDay ?? BillsEngine.defaultDueDay(for: transaction))
        _billAmount = State(initialValue: BillsEngine.resolvedAmount(for: transaction))
        _excludedFromBudget = State(initialValue: transaction.excludedFromBudget)
    }

    private var liveTransaction: Transaction {
        transactions.transactions.first { $0.id == transaction.id } ?? transaction
    }

    private var categorySource: CategorySource? {
        CategorySource.from(liveTransaction.categorySource)
    }

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Merchant", value: FinanceFormatting.displayName(for: liveTransaction))
                LabeledContent("Amount", value: TransactionFormatting.formattedAmount(liveTransaction.amount))
                LabeledContent("Type", value: TransactionFormatting.amountLabel(liveTransaction.amount))
                LabeledContent("Date", value: liveTransaction.date)
                if let subcategory = liveTransaction.subcategory, !subcategory.isEmpty {
                    LabeledContent("Subcategory", value: subcategory)
                }
                LabeledContent("Status", value: liveTransaction.pending ? "Pending" : "Posted")
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
                .disabled(isSavingCategory)

                Toggle(
                    "Remember for future purchases from this merchant",
                    isOn: $saveMerchantRule
                )
                .font(.subheadline)

                Button(isSavingCategory ? "Saving…" : "Save category") {
                    Task { await saveCategory() }
                }
                .disabled(isSavingCategory || (selectedCategory == liveTransaction.category && !saveMerchantRule))

                NavigationLink("Merchant rule library (\(merchantRules.rules.count))") {
                    CategoryRulesView()
                }

                NavigationLink("Split transaction") {
                    SplitTransactionView(transaction: liveTransaction)
                }
            }

            Section("Budget") {
                Toggle("Exclude from budget totals", isOn: $excludedFromBudget)
                    .onChange(of: excludedFromBudget) { _, _ in
                        Task { await saveBudgetExclusion() }
                    }
            } footer: {
                Text("Excluded transactions stay in your history but won't count toward category spending or the budget chart.")
            }

            Section {
                Toggle("Fixed monthly expense", isOn: $isFixedBill)
                    .onChange(of: isFixedBill) { _, isOn in
                        if isOn {
                            applyBillDefaults()
                        }
                    }
            } footer: {
                Text("Shows under Bills with a nickname and typical charge day.")
            }

            if isFixedBill {
                Section("Bill details") {
                    TextField("Nickname", text: $billNickname)
                    Picker("Typical due day", selection: $billDueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("Day \(day)").tag(day)
                        }
                    }
                    TextField("Amount", value: $billAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    Button(isSavingBill ? "Saving…" : "Save bill") {
                        Task { await saveBill() }
                    }
                    .disabled(isSavingBill || billAmount <= 0)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Category saved", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            if saveMerchantRule {
                Text("Future transactions matching “\(FinanceFormatting.displayName(for: liveTransaction))” will use \(selectedCategory).")
            } else {
                Text("Only this transaction was updated.")
            }
        }
        .alert("Bill saved", isPresented: $showBillSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(isFixedBill ? "\(billNickname) will appear under Bills." : "Removed from Bills.")
        }
        .task {
            guard let client = auth.activeSupabaseClient else { return }
            if merchantRules.rules.isEmpty {
                await merchantRules.reload(client: client)
            }
            syncBillDraftFromStore()
        }
    }

    private func applyBillDefaults() {
        billNickname = FinanceFormatting.displayName(for: liveTransaction)
        billDueDay = BillsEngine.defaultDueDay(for: liveTransaction)
        billAmount = abs(liveTransaction.amount)
    }

    private func syncBillDraftFromStore() {
        let txn = liveTransaction
        isFixedBill = txn.isFixedBill
        billNickname = BillsEngine.displayName(for: txn)
        billDueDay = BillsEngine.resolvedDueDay(for: txn, transactions: transactions.transactions)
        billAmount = BillsEngine.resolvedAmount(for: txn)
        selectedCategory = txn.category
        excludedFromBudget = txn.excludedFromBudget
    }

    private func saveBudgetExclusion() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.updateBudgetExclusion(
            transaction: liveTransaction,
            excludedFromBudget: excludedFromBudget,
            client: client
        )
    }

    private func saveCategory() async {
        guard let client = auth.activeSupabaseClient else { return }
        isSavingCategory = true
        defer { isSavingCategory = false }
        await transactions.updateCategory(
            transaction: liveTransaction,
            category: selectedCategory,
            saveMerchantRule: saveMerchantRule,
            merchantRules: merchantRules,
            client: client
        )
        if transactions.errorMessage == nil {
            showSavedConfirmation = true
        }
    }

    private func saveBill() async {
        guard let client = auth.activeSupabaseClient else { return }
        isSavingBill = true
        defer { isSavingBill = false }

        let trimmedNickname = billNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        await transactions.updateBillSettings(
            transaction: liveTransaction,
            isFixedBill: isFixedBill,
            billNickname: isFixedBill && !trimmedNickname.isEmpty ? trimmedNickname : nil,
            billDueDay: isFixedBill ? billDueDay : nil,
            billAmount: isFixedBill ? billAmount : nil,
            client: client
        )
        if transactions.errorMessage == nil {
            showBillSavedConfirmation = true
        }
    }
}
