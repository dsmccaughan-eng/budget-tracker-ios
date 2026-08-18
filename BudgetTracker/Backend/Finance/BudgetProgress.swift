import Foundation

struct BudgetProgress: Equatable, Identifiable {
    var id: String { category }
    let category: String
    let monthlyLimit: Double
    let spent: Double
    let projectedSpend: Double
    let typicalByNow: Double
    let isFixed: Bool
    let isRollover: Bool
    let color: String

    init(
        category: String,
        monthlyLimit: Double,
        spent: Double,
        projectedSpend: Double,
        typicalByNow: Double = 0,
        isFixed: Bool,
        isRollover: Bool,
        color: String
    ) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.spent = spent
        self.projectedSpend = projectedSpend
        self.typicalByNow = typicalByNow
        self.isFixed = isFixed
        self.isRollover = isRollover
        self.color = color
    }

    var remaining: Double { monthlyLimit - spent }
    var percentUsed: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(spent / monthlyLimit, 1.5)
    }
    var isOverBudget: Bool { spent > monthlyLimit }
    var isAheadOfTypical: Bool { typicalByNow > 0 && listDisplaySpent > typicalByNow }
    var showsBudgetLimit: Bool { monthlyLimit > 0 }

    var listDisplaySpent: Double {
        BudgetMath.listDisplaySpent(category: category, netAmount: spent)
    }
}

struct BudgetChartSliceSegment: Equatable {
    let progress: BudgetProgress
    let amount: Double
    let startFraction: Double
    let endFraction: Double
}
