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
                                    await budgets.deleteBudget(
                                        budget,
                                        client: auth.supabaseClient,
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
            .sheet(isPresented: $showAddBudget) {
                NavigationStack {
                    AddBudgetView()
                }
            }
            .refreshable {
                await transactions.loadAll(client: auth.supabaseClient)
                await budgets.reload(client: auth.supabaseClient, transactions: transactions.transactions)
            }
            .task {
                await budgets.reload(client: auth.supabaseClient, transactions: transactions.transactions)
            }
        }
    }
}

struct AddBudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = BudgetDraft()
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Text("Choose a category and monthly limit. Spending from synced transactions counts toward each budget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Category") {
                Picker("Category", selection: $draft.category) {
                    ForEach(BudgetCategories.all, id: \.self) { category in
                        Text(category).tag(category)
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
        }
        .navigationTitle("Add Budget")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving || draft.monthlyLimit <= 0)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await budgets.addBudget(draft, client: auth.supabaseClient, transactions: transactions.transactions)
        if budgets.errorMessage == nil { dismiss() }
    }
}
