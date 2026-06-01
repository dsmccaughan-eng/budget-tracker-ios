import Foundation
import Supabase

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var progress: [BudgetProgress] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func setClientError(_ message: String) {
        errorMessage = message
    }

    func reload(client: SupabaseClient, transactions: [Transaction]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            budgets = try await SupabaseService.shared.fetchBudgets(client: client)
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addBudget(_ draft: BudgetDraft, client: SupabaseClient, transactions: [Transaction]) async {
        errorMessage = nil
        if budgets.contains(where: { $0.category == draft.category }) {
            errorMessage = "You already have a budget for \(draft.category)."
            return
        }
        do {
            let budget = Budget(
                id: UUID(),
                category: draft.category,
                monthlyLimit: draft.monthlyLimit,
                color: draft.color,
                isRollover: draft.isRollover,
                isFixed: draft.isFixed
            )
            let saved = try await SupabaseService.shared.saveBudget(budget, client: client)
            budgets.append(saved)
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBudget(
        _ budget: Budget,
        client: SupabaseClient,
        transactions: [Transaction]
    ) async {
        errorMessage = nil
        do {
            let saved = try await SupabaseService.shared.updateBudget(budget, client: client)
            if let index = budgets.firstIndex(where: { $0.id == budget.id }) {
                budgets[index] = saved
            }
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteBudget(_ budget: Budget, client: SupabaseClient, transactions: [Transaction]) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.deleteBudget(id: budget.id, client: client)
            budgets.removeAll { $0.id == budget.id }
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recomputeProgress(transactions: [Transaction]) {
        progress = BudgetMath.progressRows(budgets: budgets, transactions: transactions)
    }
}

struct BudgetDraft {
    var category: String = BudgetCategories.all.first ?? "Groceries"
    var monthlyLimit: Double = 500
    var color: String = BudgetPalette.defaultColor
    var isRollover: Bool = false
    var isFixed: Bool = false
}

enum BudgetPalette {
    static let defaultColor = "#3b82f6"
    static let colors = [
        "#3b82f6", "#22c55e", "#f97316", "#a855f7",
        "#ef4444", "#14b8a6", "#eab308", "#64748b"
    ]
}
