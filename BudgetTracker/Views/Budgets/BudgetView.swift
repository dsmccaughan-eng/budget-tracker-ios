import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    var body: some View {
        NavigationStack {
            List {
                if budgets.progress.isEmpty {
                    ContentUnavailableView(
                        "No budgets yet",
                        systemImage: "dollarsign.circle",
                        description: Text("Add monthly limits to track spending by category.")
                    )
                } else {
                    Section("This month") {
                        ForEach(budgets.budgets) { budget in
                            if let row = budgets.progress.first(where: { $0.category == budget.category }) {
                                BudgetProgressBar(progress: row)
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
                    NavigationLink {
                        AddBudgetView()
                    } label: {
                        Image(systemName: "plus")
                    }
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
