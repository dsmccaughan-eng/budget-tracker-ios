import SwiftUI

struct SetupBudgetPlanView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @Environment(\.dismiss) private var dismiss

    @State private var totalBudget: Double = 0
    @State private var lines: [BudgetPlanLine] = []
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var didLoadDraft = false

    var body: some View {
        Form {
            Section {
                Text("Set your monthly total once. Amounts split across every spending category with colors assigned automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Monthly total") {
                TextField("Total budget", value: $totalBudget, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .onChange(of: totalBudget) { _, newValue in
                        guard didLoadDraft, newValue > 0 else { return }
                        lines = BudgetMath.scaledPlanLines(lines, total: newValue)
                    }
            }

            Section {
                HStack {
                    Text("Allocated")
                    Spacer()
                    Text(FinanceFormatting.currency(lines.reduce(0) { $0 + $1.monthlyLimit }))
                        .foregroundStyle(allocationMatchesTotal ? Color.secondary : Color.orange)
                }
                Button("Match recent spending") {
                    applySuggestedPlan()
                }
            }

            Section("Category breakdown") {
                ForEach(lines.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: lines[index].color))
                            .frame(width: 12, height: 12)
                        Text(lines[index].category)
                            .font(.subheadline)
                        Spacer()
                        TextField(
                            "Amount",
                            value: Binding(
                                get: { lines[index].monthlyLimit },
                                set: { newValue in
                                    lines[index].monthlyLimit = newValue
                                    guard didLoadDraft else { return }
                                    totalBudget = lines.reduce(0) { $0 + $1.monthlyLimit }
                                }
                            ),
                            format: .currency(code: "USD")
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    }
                }
            }

            if let errorMessage = budgets.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Budget plan")
        .onAppear(perform: loadDraftIfNeeded)
        .alert("Could not save budget plan", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(budgets.errorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save plan") {
                    Task { await save() }
                }
                .disabled(isSaving || totalBudget <= 0 || lines.isEmpty)
            }
        }
    }

    private var allocationMatchesTotal: Bool {
        abs(lines.reduce(0) { $0 + $1.monthlyLimit } - totalBudget) < 0.02
    }

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        if budgets.budgets.isEmpty {
            let suggestedTotal = max(
                BudgetMath.suggestedPlanLines(
                    total: 3000,
                    transactions: transactions.transactions
                ).reduce(0) { $0 + $1.monthlyLimit },
                3000
            )
            totalBudget = suggestedTotal
            lines = BudgetMath.suggestedPlanLines(
                total: suggestedTotal,
                transactions: transactions.transactions
            )
        } else {
            lines = BudgetMath.budgetableCategories.enumerated().map { offset, category in
                if let existing = budgets.budgets.first(where: { $0.category == category }) {
                    return BudgetPlanLine(
                        category: category,
                        monthlyLimit: existing.monthlyLimit,
                        color: existing.color
                    )
                }
                return BudgetPlanLine(
                    category: category,
                    monthlyLimit: 0,
                    color: BudgetPalette.color(at: offset)
                )
            }
            totalBudget = lines.reduce(0) { $0 + $1.monthlyLimit }
            if totalBudget <= 0 {
                applySuggestedPlan(defaultTotal: 3000)
            }
        }
        didLoadDraft = true
    }

    private func applySuggestedPlan(defaultTotal: Double = 0) {
        let baseTotal = totalBudget > 0 ? totalBudget : defaultTotal
        lines = BudgetMath.suggestedPlanLines(
            total: baseTotal,
            transactions: transactions.transactions,
            existingBudgets: budgets.budgets
        )
        totalBudget = lines.reduce(0) { $0 + $1.monthlyLimit }
    }

    private func save() async {
        guard let client = auth.activeSupabaseClient else {
            budgets.setClientError("Sign in again to save budgets.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        await budgets.applyBudgetPlan(
            lines: lines,
            client: client,
            transactions: transactions.transactions
        )
        if budgets.errorMessage == nil {
            dismiss()
        } else {
            showSaveError = true
        }
    }
}
