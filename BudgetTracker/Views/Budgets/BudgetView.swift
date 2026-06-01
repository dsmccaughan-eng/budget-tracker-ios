import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    @State private var showAddBudget = false
    @State private var budgetToEdit: Budget?
    @State private var selectedMonth = BudgetMath.startOfMonth(Date())

    private var monthProgress: [BudgetProgress] {
        BudgetMath.progressRows(
            budgets: budgets.budgets,
            transactions: transactions.transactions,
            referenceDate: selectedMonth
        )
    }

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
                        BudgetMonthNavigator(selectedMonth: $selectedMonth)
                        BudgetSpendPieChart(
                            progress: monthProgress,
                            referenceDate: selectedMonth,
                            hasTransactions: !transactions.transactions.isEmpty
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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

                    Section(monthSectionTitle) {
                        ForEach(budgets.budgets) { budget in
                            if let row = monthProgress.first(where: { $0.category == budget.category }) {
                                Button {
                                    budgetToEdit = budget
                                } label: {
                                    BudgetCategorySpendRow(
                                        progress: row,
                                        recentSummary: BudgetMath.recentMerchantSummary(
                                            transactions: transactions.transactions,
                                            category: row.category,
                                            referenceDate: selectedMonth
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit budget", systemImage: "pencil") {
                                        budgetToEdit = budget
                                    }
                                    Button("Delete budget", systemImage: "trash", role: .destructive) {
                                        Task { await deleteBudget(budget) }
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    await deleteBudget(budgets.budgets[index])
                                }
                            }
                        }
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
            .sheet(item: $budgetToEdit, onDismiss: {
                Task { await reloadBudgetsTab() }
            }) { budget in
                NavigationStack {
                    EditBudgetView(budget: budget)
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

    private var monthSectionTitle: String {
        let current = BudgetMath.startOfMonth(Date())
        let selected = BudgetMath.startOfMonth(selectedMonth)
        if selected == current {
            return "This month"
        }
        return selected.formatted(.dateTime.month(.wide).year())
    }

    private var fixedBills: [BillItem] {
        BillsEngine.bills(
            budgets: budgets.budgets,
            transactions: transactions.transactions,
            referenceDate: selectedMonth
        )
    }

    private var billsSummaryLabel: String {
        let dueCount = fixedBills.filter { !$0.isPaid }.count
        if dueCount == 0 {
            return "View all bills"
        }
        return "\(dueCount) bill\(dueCount == 1 ? "" : "s") due"
    }

    private func deleteBudget(_ budget: Budget) async {
        guard let client = auth.activeSupabaseClient else { return }
        await budgets.deleteBudget(
            budget,
            client: client,
            transactions: transactions.transactions
        )
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

            budgetLimitSections

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

    @ViewBuilder
    private var budgetLimitSections: some View {
        Section("Limit") {
            TextField("Monthly limit", value: $draft.monthlyLimit, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
            Toggle("Fixed expense", isOn: $draft.isFixed)
            Toggle("Rollover unused", isOn: $draft.isRollover)
        }

        Section("Color") {
            BudgetColorPicker(selection: $draft.color)
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

struct EditBudgetView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @Environment(\.dismiss) private var dismiss

    let budget: Budget

    @State private var monthlyLimit: Double
    @State private var color: String
    @State private var isFixed: Bool
    @State private var isRollover: Bool
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var showDeleteConfirm = false

    init(budget: Budget) {
        self.budget = budget
        _monthlyLimit = State(initialValue: budget.monthlyLimit)
        _color = State(initialValue: budget.color)
        _isFixed = State(initialValue: budget.isFixed)
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
                Toggle("Fixed expense", isOn: $isFixed)
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
        updated.isFixed = isFixed
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
