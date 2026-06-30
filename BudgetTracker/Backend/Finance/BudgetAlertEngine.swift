import Foundation

enum BudgetAlertEngine {
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
        progress.compactMap { row in
            guard !suppressesAlerts(row, fixedBillCategories: fixedBillCategories) else { return nil }
            if row.isOverBudget {
                return "\(row.category) is over budget."
            }
            if row.percentUsed >= threshold {
                return "\(row.category) has used \(Int(row.percentUsed * 100))% of its budget."
            }
            return nil
        }
    }

    private static func suppressesAlerts(
        _ row: BudgetProgress,
        fixedBillCategories: Set<String>
    ) -> Bool {
        row.isFixed || fixedBillCategories.contains(row.category)
    }
}
