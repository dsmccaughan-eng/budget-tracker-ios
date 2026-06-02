import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    @State private var showBudgetPlan = false
    @State private var budgetToEdit: Budget?
    @State private var monthOffset = 0

    private var selectedMonth: Date {
        let current = BudgetMath.startOfMonth(Date())
        return Calendar.current.date(byAdding: .month, value: -monthOffset, to: current) ?? current
    }

    private var monthSections: BudgetMonthSections {
        budgets.displayMonthSections(referenceDate: selectedMonth, transactions: transactions.transactions)
    }

    private var chartProgress: [BudgetProgress] {
        budgets.monthRows(referenceDate: selectedMonth, transactions: transactions.transactions)
            .map(\.progress)
    }

    var body: some View {
        NavigationStack {
            List {
                if budgets.budgets.isEmpty {
                    ContentUnavailableView {
                        Label("No budgets yet", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Set a monthly total and we’ll split it across every spending category automatically.")
                    } actions: {
                        Button("Set up budget plan") {
                            showBudgetPlan = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Section {
                        BudgetMonthNavigator(monthOffset: $monthOffset)
                        BudgetSpendPieChart(
                            progress: chartProgress,
                            referenceDate: selectedMonth,
                            hasTransactions: !transactions.transactions.isEmpty
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                    budgetCategorySection(
                        title: monthSectionTitle,
                        rows: monthSections.spending,
                        allowsDelete: true
                    )

                    if !monthSections.income.isEmpty {
                        budgetCategorySection(
                            title: "Income",
                            rows: monthSections.income,
                            allowsDelete: false
                        )
                    }

                    if !monthSections.transfers.isEmpty {
                        budgetCategorySection(
                            title: "Transfers",
                            rows: monthSections.transfers,
                            allowsDelete: false
                        )
                    }
                }

                if !budgets.budgets.isEmpty {
                    Section {
                        NavigationLink("Budget history") {
                            BudgetHistoryView()
                        }
                    }
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !budgets.budgets.isEmpty {
                        EditButton()
                    }
                    Button("Plan", systemImage: budgets.budgets.isEmpty ? "plus" : "slider.horizontal.3") {
                        showBudgetPlan = true
                    }
                }
            }
            .sheet(isPresented: $showBudgetPlan, onDismiss: {
                budgets.recomputeProgress(transactions: transactions.transactions)
            }) {
                NavigationStack {
                    SetupBudgetPlanView()
                }
            }
            .sheet(item: $budgetToEdit, onDismiss: {
                budgets.recomputeProgress(transactions: transactions.transactions)
            }) { budget in
                NavigationStack {
                    EditBudgetView(budget: budget)
                }
            }
            .refreshable {
                await reloadBudgetsTab()
            }
            .task {
                await reloadBudgetsTabIfNeeded()
            }
            .onChange(of: transactions.transactions) { _, newTransactions in
                budgets.noteTransactionsChanged(newTransactions)
            }
        }
    }

    private var monthSectionTitle: String {
        let current = BudgetMath.startOfMonth(Date())
        let selected = BudgetMath.startOfMonth(selectedMonth)
        if selected == current {
            return "This month"
        }
        return selected.formatted(.dateTime.month(.wide).year())
    }

    @ViewBuilder
    private func budgetCategorySection(
        title: String,
        rows: [BudgetMonthRow],
        allowsDelete: Bool
    ) -> some View {
        if allowsDelete {
            Section(title) {
                ForEach(rows) { row in
                    budgetCategoryRow(row)
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            let category = rows[index].progress.category
                            if let budget = budgets.budgets.first(where: { $0.category == category }) {
                                await deleteBudget(budget)
                            }
                        }
                    }
                }
            }
        } else {
            Section(title) {
                ForEach(rows) { row in
                    budgetCategoryRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func budgetCategoryRow(_ row: BudgetMonthRow) -> some View {
        NavigationLink {
            CategoryTransactionsView(
                category: row.progress.category,
                referenceMonth: selectedMonth
            )
        } label: {
            BudgetCategorySpendRow(
                progress: row.progress,
                recentSummary: row.recentSummary
            )
        }
        .contextMenu {
            if let budget = budgets.budgets.first(where: { $0.category == row.progress.category }) {
                Button("Edit budget", systemImage: "pencil") {
                    budgetToEdit = budget
                }
                Button("Delete budget", systemImage: "trash", role: .destructive) {
                    Task { await deleteBudget(budget) }
                }
            }
        }
    }

    private func deleteBudget(_ budget: Budget) async {
        guard let client = auth.activeSupabaseClient else { return }
        await budgets.deleteBudget(
            budget,
            client: client,
            transactions: transactions.transactions
        )
    }

    private func reloadBudgetsTabIfNeeded() async {
        guard let client = auth.activeSupabaseClient else { return }
        if budgets.budgets.isEmpty || budgets.isLoading {
            await budgets.reload(client: client, transactions: transactions.transactions)
        } else {
            budgets.recomputeProgress(transactions: transactions.transactions)
        }
    }

    private func reloadBudgetsTab() async {
        guard let client = auth.activeSupabaseClient else { return }
        if transactions.transactions.isEmpty {
            await transactions.loadAll(client: client)
        }
        await budgets.reload(client: client, transactions: transactions.transactions)
    }
}

struct EditBudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @Environment(\.dismiss) private var dismiss

    let budget: Budget

    @State private var monthlyLimit: Double
    @State private var color: String
    @State private var isRollover: Bool
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var showDeleteConfirm = false

    init(budget: Budget) {
        self.budget = budget
        _monthlyLimit = State(initialValue: budget.monthlyLimit)
        _color = State(initialValue: budget.color)
        _isRollover = State(initialValue: budget.isRollover)
    }

    var body: some View {
        Form {
            Section("Category") {
                Text(budget.category)
                    .foregroundStyle(.secondary)
            }

            Section("Limit") {
                TextField("Monthly limit", value: $monthlyLimit, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                Toggle("Rollover unused", isOn: $isRollover)
            }

            Section("Color") {
                BudgetColorPicker(selection: $color)
            }

            Section {
                Button("Delete budget", role: .destructive) {
                    showDeleteConfirm = true
                }
            }

            if let errorMessage = budgets.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Budget")
        .alert("Could not save budget", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(budgets.errorMessage ?? "Try again.")
        }
        .confirmationDialog(
            "Delete this budget?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteBudget() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can add \(budget.category) again later.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving || monthlyLimit <= 0)
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
        var updated = budget
        updated.monthlyLimit = monthlyLimit
        updated.color = color
        updated.isRollover = isRollover
        await budgets.updateBudget(updated, client: client, transactions: transactions.transactions)
        if budgets.errorMessage == nil {
            dismiss()
        } else {
            showSaveError = true
        }
    }

    private func deleteBudget() async {
        guard let client = auth.activeSupabaseClient else { return }
        isSaving = true
        defer { isSaving = false }
        await budgets.deleteBudget(budget, client: client, transactions: transactions.transactions)
        if budgets.errorMessage == nil {
            dismiss()
        } else {
            showSaveError = true
        }
    }
}

private struct BudgetColorPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
            ForEach(BudgetPalette.colors, id: \.self) { color in
                Circle()
                    .fill(Color(hex: color))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if selection == color {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .font(.caption.bold())
                        }
                    }
                    .onTapGesture { selection = color }
            }
        }
        .padding(.vertical, 4)
    }
}
