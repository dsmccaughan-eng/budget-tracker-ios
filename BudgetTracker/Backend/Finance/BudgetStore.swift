import Foundation
import Supabase

@MainActor
final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var progress: [BudgetProgress] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var spendIndex: BudgetSpendIndex?
    private var indexedFingerprint: Int?
    private var cachedMonthRowsByKey: [String: [BudgetMonthRow]] = [:]
    private var cachedMonthSectionsByKey: [String: BudgetMonthSections] = [:]

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
        rows(referenceDate: referenceDate, transactions: transactions, displayMode: .chart)
    }

    func displayMonthRows(referenceDate: Date, transactions: [Transaction]) -> [BudgetMonthRow] {
        rows(referenceDate: referenceDate, transactions: transactions, displayMode: .list)
    }

    func displayMonthSections(referenceDate: Date, transactions: [Transaction]) -> BudgetMonthSections {
        ensureIndex(transactions: transactions)
        let cacheKey = listCacheKey(referenceDate: referenceDate, transactions: transactions)
        if let cached = cachedMonthSectionsByKey[cacheKey] {
            return cached
        }
        guard let index = spendIndex else {
            return BudgetMonthSections(spending: [], income: [], transfers: [])
        }
        let sections = BudgetMath.displayMonthSections(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate
        )
        cachedMonthSectionsByKey[cacheKey] = sections
        return sections
    }

    private enum MonthRowDisplayMode {
        case chart
        case list
    }

    private func rows(
        referenceDate: Date,
        transactions: [Transaction],
        displayMode: MonthRowDisplayMode
    ) -> [BudgetMonthRow] {
        ensureIndex(transactions: transactions)
        let modeKey = displayMode == .chart ? "chart" : "list"
        let key = monthCacheKey(prefix: modeKey, referenceDate: referenceDate, transactions: transactions)
        if let cached = cachedMonthRowsByKey[key] {
            return cached
        }
        guard let index = spendIndex else { return [] }
        let rows: [BudgetMonthRow]
        switch displayMode {
        case .chart:
            rows = BudgetMath.monthRows(
                budgets: budgets,
                index: index,
                referenceDate: referenceDate
            )
        case .list:
            rows = BudgetMath.displayMonthRows(
                budgets: budgets,
                index: index,
                referenceDate: referenceDate
            )
        }
        cachedMonthRowsByKey[key] = rows
        return rows
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
                    budget.color = BudgetPalette.color(forCategory: line.category)
                    let saved = try await SupabaseService.shared.updateBudget(budget, client: client)
                    if let index = updatedBudgets.firstIndex(where: { $0.id == saved.id }) {
                        updatedBudgets[index] = saved
                    }
                } else {
                    let budget = Budget(
                        id: UUID(),
                        category: line.category,
                        monthlyLimit: line.monthlyLimit,
                        color: BudgetPalette.color(forCategory: line.category),
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

    func noteTransactionsChanged(_ transactions: [Transaction]) {
        ensureIndex(transactions: transactions)
        recomputeProgress(transactions: transactions)
    }

    private func ensureIndex(transactions: [Transaction]) {
        let fingerprint = Self.transactionsFingerprint(transactions)
        if spendIndex == nil || indexedFingerprint != fingerprint {
            spendIndex = BudgetSpendIndex(transactions: transactions)
            indexedFingerprint = fingerprint
            invalidateMonthCache()
        }
    }

    private static func transactionsFingerprint(_ transactions: [Transaction]) -> Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        for txn in transactions {
            hasher.combine(txn.id)
            hasher.combine(txn.category)
            hasher.combine(txn.amount)
            hasher.combine(txn.date)
            hasher.combine(txn.isFixedBill)
            hasher.combine(txn.billDueDay)
            hasher.combine(txn.billAmount)
            hasher.combine(txn.excludedFromBudget)
        }
        return hasher.finalize()
    }

    private func listCacheKey(referenceDate: Date, transactions: [Transaction]) -> String {
        monthCacheKey(prefix: "list", referenceDate: referenceDate, transactions: transactions)
    }

    private func monthCacheKey(
        prefix: String,
        referenceDate: Date,
        transactions: [Transaction]
    ) -> String {
        let base = BudgetMath.cacheKey(
            referenceDate: referenceDate,
            transactionCount: transactions.count,
            budgets: budgets
        )
        return "\(prefix)-\(base)"
    }

    private func invalidateMonthCache() {
        cachedMonthRowsByKey = [:]
        cachedMonthSectionsByKey = [:]
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
    static let defaultColor = "#2563eb"
    static let colors = [
        "#2563eb", "#16a34a", "#ea580c", "#9333ea", "#dc2626",
        "#0891b2", "#ca8a04", "#64748b", "#db2777", "#059669",
        "#7c3aed", "#c2410c", "#0d9488", "#4f46e5", "#b45309",
        "#0369a1", "#be123c", "#15803d", "#57534e"
    ]

    static func color(at index: Int) -> String {
        colors[index % colors.count]
    }

    static func color(forCategory category: String) -> String {
        guard let index = BudgetCategories.all.firstIndex(of: category) else {
            return defaultColor
        }
        return color(at: index)
    }
}
