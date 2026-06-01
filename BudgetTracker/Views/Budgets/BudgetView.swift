import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    @State private var showAddBudget = false

    var body: some View {
        NavigationStack {
            List {
                if budgets.progress.isEmpty {
                    ContentUnavailableView {
                        Label("No budgets yet", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Set a monthly spending limit for each category (Groceries, Dining, etc.) to track progress.")
                    } actions: {
                        Button("Add monthly budget") {
                            showAddBudget = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Section {
                        BudgetSpendPieChart(progress: budgets.progress, referenceDate: Date())
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if !fixedBills.isEmpty {
                        Section("Bills this month") {
                            NavigationLink {
                                BillsListView()
                            } label: {
                                Label(billsSummaryLabel, systemImage: "calendar")
                            }
                            ForEach(fixedBills.prefix(3)) { bill in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bill.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(bill.displayDue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(FinanceFormatting.currency(bill.amount))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }

                    Section("This month") {
                        ForEach(budgets.budgets) { budget in
                            if let row = budgets.progress.first(where: { $0.category == budget.category }) {
                                BudgetCategorySpendRow(
                                    progress: row,
                                    recentSummary: BudgetMath.recentMerchantSummary(
                                        transactions: transactions.transactions,
                                        category: row.category
                                    )
                                )
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let budget = budgets.budgets[index]
                                    guard let client = auth.activeSupabaseClient else { return }
                                    await budgets.deleteBudget(
                                        budget,
                                        client: client,
                                        transactions: transactions.transactions
                                    )
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink("Budget history") {
                        BudgetHistoryView()
                    }
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        showAddBudget = true
                    }
                }
            }
            .sheet(isPresented: $showAddBudget, onDismiss: {
                Task { await reloadBudgetsTab() }
            }) {
                NavigationStack {
                    AddBudgetView()
                }
            }
            .refreshable {
                await reloadBudgetsTab()
            }
            .task {
                await reloadBudgetsTab()
            }
        }
    }

    private var fixedBills: [BillItem] {
        BillsEngine.bills(
            budgets: budgets.budgets,
            transactions: transactions.transactions
        )
    }

    private var billsSummaryLabel: String {
        let dueCount = fixedBills.filter { !$0.isPaid }.count
        if dueCount == 0 {
            return "View all bills"
        }
        return "\(dueCount) bill\(dueCount == 1 ? "" : "s") due"
    }

    private func reloadBudgetsTab() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.loadAll(client: client)
        await budgets.reload(client: client, transactions: transactions.transactions)
    }
}

struct AddBudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = BudgetDraft()
    @State private var isSaving = false
    @State private var showSaveError = false

    private var availableCategories: [String] {
        let used = Set(budgets.budgets.map(\.category))
        return BudgetCategories.all.filter { !used.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                Text("Choose a category and monthly limit. Spending from synced transactions counts toward each budget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Category") {
                if availableCategories.isEmpty {
                    Text("Every category already has a budget.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Category", selection: $draft.category) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .onAppear {
                        if !availableCategories.contains(draft.category),
                           let first = availableCategories.first {
                            draft.category = first
                        }
                    }
                }
            }

            Section("Limit") {
                TextField("Monthly limit", value: $draft.monthlyLimit, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                Toggle("Fixed expense", isOn: $draft.isFixed)
                Toggle("Rollover unused", isOn: $draft.isRollover)
            }

            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                    ForEach(BudgetPalette.colors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if draft.color == color {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .font(.caption.bold())
                                }
                            }
                            .onTapGesture { draft.color = color }
                    }
                }
                .padding(.vertical, 4)
            }

            if let errorMessage = budgets.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Budget")
        .alert("Could not save budget", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(budgets.errorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving || draft.monthlyLimit <= 0 || availableCategories.isEmpty)
            }
        }
    }

    private func save() async {
        guard let client = auth.activeSupabaseClient else {
            budgets.setClientError("Sign in again to save budgets.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        await budgets.addBudget(draft, client: client, transactions: transactions.transactions)
        if budgets.errorMessage == nil {
            dismiss()
        } else {
            showSaveError = true
        }
    }
}
