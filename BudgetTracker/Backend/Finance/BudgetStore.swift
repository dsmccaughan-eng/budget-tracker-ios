import Foundation
import Supabase

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var progress: [BudgetProgress] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var spendIndex: BudgetSpendIndex?
    private var indexedTransactionCount = -1
    private var cachedMonthKey: String?
    private var cachedMonthRows: [BudgetMonthRow] = []

    func setClientError(_ message: String) {
        errorMessage = message
    }

    func reload(client: SupabaseClient, transactions: [Transaction]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            budgets = try await SupabaseService.shared.fetchBudgets(client: client)
            invalidateMonthCache()
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func monthRows(referenceDate: Date, transactions: [Transaction]) -> [BudgetMonthRow] {
        ensureIndex(transactions: transactions)
        let key = BudgetMath.cacheKey(
            referenceDate: referenceDate,
            transactionCount: transactions.count,
            budgets: budgets
        )
        if key == cachedMonthKey {
            return cachedMonthRows
        }
        guard let index = spendIndex else { return [] }
        cachedMonthKey = key
        cachedMonthRows = BudgetMath.monthRows(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate
        )
        return cachedMonthRows
    }

    func monthProgress(referenceDate: Date, transactions: [Transaction]) -> [BudgetProgress] {
        monthRows(referenceDate: referenceDate, transactions: transactions).map(\.progress)
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
            invalidateMonthCache()
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyBudgetPlan(
        lines: [BudgetPlanLine],
        client: SupabaseClient,
        transactions: [Transaction]
    ) async {
        errorMessage = nil
        let limitsByCategory = Dictionary(uniqueKeysWithValues: lines.map { ($0.category, $0.monthlyLimit) })
        let meaningful = lines.filter { $0.monthlyLimit > 0 }
        guard !meaningful.isEmpty else {
            errorMessage = "Enter a total budget and at least one category amount."
            return
        }

        var updatedBudgets = budgets
        do {
            for budget in budgets {
                let limit = limitsByCategory[budget.category, default: 0]
                guard limit <= 0 else { continue }
                try await SupabaseService.shared.deleteBudget(id: budget.id, client: client)
                updatedBudgets.removeAll { $0.id == budget.id }
            }

            for line in meaningful {
                if let existing = updatedBudgets.first(where: { $0.category == line.category }) {
                    var budget = existing
                    budget.monthlyLimit = line.monthlyLimit
                    budget.color = line.color
                    let saved = try await SupabaseService.shared.updateBudget(budget, client: client)
                    if let index = updatedBudgets.firstIndex(where: { $0.id == saved.id }) {
                        updatedBudgets[index] = saved
                    }
                } else {
                    let budget = Budget(
                        id: UUID(),
                        category: line.category,
                        monthlyLimit: line.monthlyLimit,
                        color: line.color,
                        isRollover: false,
                        isFixed: false
                    )
                    let saved = try await SupabaseService.shared.saveBudget(budget, client: client)
                    updatedBudgets.append(saved)
                }
            }
            budgets = updatedBudgets.sorted { $0.category < $1.category }
            invalidateMonthCache()
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
            invalidateMonthCache()
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
            invalidateMonthCache()
            recomputeProgress(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recomputeProgress(transactions: [Transaction]) {
        ensureIndex(transactions: transactions)
        guard let index = spendIndex else {
            progress = []
            return
        }
        progress = BudgetMath.monthRows(
            budgets: budgets,
            index: index,
            referenceDate: Date()
        ).map(\.progress)
    }

    private func ensureIndex(transactions: [Transaction]) {
        if spendIndex == nil || indexedTransactionCount != transactions.count {
            spendIndex = BudgetSpendIndex(transactions: transactions)
            indexedTransactionCount = transactions.count
            invalidateMonthCache()
        }
    }

    private func invalidateMonthCache() {
        cachedMonthKey = nil
        cachedMonthRows = []
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

    static func color(at index: Int) -> String {
        colors[index % colors.count]
    }
}
