import Foundation

enum BudgetAlertEngine {
    /// Discretionary categories that surface pace / over-budget alerts.
    static let alertableCategories: Set<String> = [
        "Groceries",
        "Dining & Bars",
        "Shopping",
        "Entertainment",
        "Transport",
    ]

    static func fixedBillCategories(from transactions: [Transaction]) -> Set<String> {
        Set(transactions.filter(\.isFixedBill).map(\.category))
    }

    static func alerts(
        progress: [BudgetProgress],
        transactions: [Transaction] = [],
        threshold: Double = 0.8
    ) -> [String] {
        alerts(
            progress: progress,
            threshold: threshold,
            fixedBillCategories: fixedBillCategories(from: transactions)
        )
    }

    static func alerts(
        progress: [BudgetProgress],
        threshold: Double = 0.8,
        fixedBillCategories: Set<String>
    ) -> [String] {
        _ = threshold
        var messages: [String] = []
        if let overall = overallAlert(progress: progress, fixedBillCategories: fixedBillCategories) {
            messages.append(overall)
        }
        messages += progress.compactMap { row in
            categoryAlert(row, fixedBillCategories: fixedBillCategories)
        }
        return messages
    }

    private static func overallAlert(
        progress: [BudgetProgress],
        fixedBillCategories: Set<String>
    ) -> String? {
        let spending = progress.filter { row in
            !BudgetMath.excludedCategories.contains(row.category)
                && !suppressesAlerts(row, fixedBillCategories: fixedBillCategories)
        }
        guard !spending.isEmpty else { return nil }
        let budgeted = spending.filter(\.showsBudgetLimit)
        let budgetedSpent = budgeted.reduce(0) { $0 + $1.listDisplaySpent }
        let limit = budgeted.reduce(0) { $0 + $1.monthlyLimit }
        let spent = spending.reduce(0) { $0 + $1.listDisplaySpent }
        let typical = spending.reduce(0) { $0 + $1.typicalByNow }
        if limit > 0, budgetedSpent > limit {
            return "Overall spending is over budget."
        }
        if typical > 0, spent > typical {
            return "Overall spending is above typical for this point in the month."
        }
        return nil
    }

    private static func categoryAlert(
        _ row: BudgetProgress,
        fixedBillCategories: Set<String>
    ) -> String? {
        guard !suppressesAlerts(row, fixedBillCategories: fixedBillCategories) else { return nil }
        if row.showsBudgetLimit, row.isOverBudget {
            return "\(row.category) is over budget."
        }
        if row.isAheadOfTypical {
            return "\(row.category) is above typical spending for this point in the month."
        }
        return nil
    }

    private static func suppressesAlerts(
        _ row: BudgetProgress,
        fixedBillCategories: Set<String>
    ) -> Bool {
        guard alertableCategories.contains(row.category) else { return true }
        return row.isFixed || fixedBillCategories.contains(row.category)
    }
}
