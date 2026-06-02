import Foundation

struct BudgetProgress: Equatable, Identifiable {
    var id: String { category }
    let category: String
    let monthlyLimit: Double
    let spent: Double
    let projectedSpend: Double
    let isFixed: Bool
    let isRollover: Bool
    let color: String

    var remaining: Double { monthlyLimit - spent }
    var percentUsed: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(spent / monthlyLimit, 1.5)
    }
    var isOverBudget: Bool { spent > monthlyLimit }
    var showsBudgetLimit: Bool { monthlyLimit > 0 }

    var listDisplaySpent: Double {
        BudgetMath.listDisplaySpent(category: category, netAmount: spent)
    }
}

enum BudgetMath {
    static let excludedCategories: Set<String> = ["Income", "Transfers"]

    static var budgetableCategories: [String] {
        BudgetCategories.all.filter { !excludedCategories.contains($0) }
    }

    static func listDisplaySpent(category: String, netAmount: Double) -> Double {
        switch category {
        case "Income":
            return max(0, -netAmount)
        case "Transfers":
            return abs(netAmount)
        default:
            return netAmount
        }
    }

    static func monthRows(
        budgets: [Budget],
        index: BudgetSpendIndex,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetMonthRow] {
        budgets.map { budget in
            let spent = index.spent(category: budget.category, referenceDate: referenceDate, calendar: calendar)
            let projected = index.averageMonthlySpend(
                category: budget.category,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let progress = BudgetProgress(
                category: budget.category,
                monthlyLimit: budget.monthlyLimit,
                spent: spent,
                projectedSpend: projected,
                isFixed: budget.isFixed,
                isRollover: budget.isRollover,
                color: budget.color
            )
            return BudgetMonthRow(
                progress: progress,
                recentSummary: index.recentMerchantSummary(
                    category: budget.category,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.progress.spent == rhs.progress.spent {
                return lhs.progress.category < rhs.progress.category
            }
            return lhs.progress.spent > rhs.progress.spent
        }
    }

    /// Budget rows plus unbudgeted, Income, and Transfers categories with activity this month.
    static func displayMonthRows(
        budgets: [Budget],
        index: BudgetSpendIndex,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetMonthRow] {
        let budgetedRows = monthRows(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let budgetedCategories = Set(budgets.map(\.category))
        let supplemental = index.categoriesWithActivity(referenceDate: referenceDate, calendar: calendar)
            .filter { !budgetedCategories.contains($0) }
            .map {
                informationalMonthRow(
                    category: $0,
                    index: index,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        return (budgetedRows + supplemental).sorted { lhs, rhs in
            let left = lhs.progress.listDisplaySpent
            let right = rhs.progress.listDisplaySpent
            if left == right {
                return lhs.progress.category < rhs.progress.category
            }
            return left > right
        }
    }

    static func groupMonthRows(_ rows: [BudgetMonthRow]) -> BudgetMonthSections {
        var spending: [BudgetMonthRow] = []
        var income: [BudgetMonthRow] = []
        var transfers: [BudgetMonthRow] = []
        for row in rows {
            switch row.progress.category {
            case "Income":
                income.append(row)
            case "Transfers":
                transfers.append(row)
            default:
                spending.append(row)
            }
        }
        return BudgetMonthSections(spending: spending, income: income, transfers: transfers)
    }

    static func displayMonthSections(
        budgets: [Budget],
        index: BudgetSpendIndex,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetMonthSections {
        groupMonthRows(
            displayMonthRows(
                budgets: budgets,
                index: index,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    private static func informationalMonthRow(
        category: String,
        index: BudgetSpendIndex,
        referenceDate: Date,
        calendar: Calendar
    ) -> BudgetMonthRow {
        let spent = index.spent(category: category, referenceDate: referenceDate, calendar: calendar)
        let progress = BudgetProgress(
            category: category,
            monthlyLimit: 0,
            spent: spent,
            projectedSpend: 0,
            isFixed: false,
            isRollover: false,
            color: BudgetPalette.color(forCategory: category)
        )
        return BudgetMonthRow(
            progress: progress,
            recentSummary: index.recentMerchantSummary(
                category: category,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    /// Split `total` across budgetable categories using recent spend weights (or equal if no history).
    static func suggestedPlanLines(
        total: Double,
        transactions: [Transaction],
        existingBudgets: [Budget] = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetPlanLine] {
        let index = BudgetSpendIndex(transactions: transactions, calendar: calendar)
        let categories = budgetableCategories
        let existingByCategory = Dictionary(uniqueKeysWithValues: existingBudgets.map { ($0.category, $0) })

        var weights: [String: Double] = [:]
        for category in categories {
            if let existing = existingByCategory[category], existing.monthlyLimit > 0 {
                weights[category] = existing.monthlyLimit
            } else {
                let average = index.averageMonthlySpend(
                    category: category,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                weights[category] = average
            }
        }

        let weightSum = weights.values.reduce(0, +)
        let evenShare = total / Double(max(categories.count, 1))
        var lines: [BudgetPlanLine] = []
        var assigned = 0.0

        for (offset, category) in categories.enumerated() {
            let color = BudgetPalette.color(forCategory: category)
            let limit: Double
            if weightSum > 0 {
                let raw = total * (weights[category, default: 0] / weightSum)
                limit = offset == categories.count - 1
                    ? max(0, total - assigned)
                    : (raw * 100).rounded() / 100
            } else {
                limit = offset == categories.count - 1
                    ? max(0, total - assigned)
                    : (evenShare * 100).rounded() / 100
            }
            assigned += limit
            lines.append(BudgetPlanLine(category: category, monthlyLimit: limit, color: color))
        }
        return lines
    }

    static func scaledPlanLines(
        _ lines: [BudgetPlanLine],
        total: Double
    ) -> [BudgetPlanLine] {
        let currentTotal = lines.reduce(0) { $0 + $1.monthlyLimit }
        guard currentTotal > 0 else {
            let even = total / Double(max(lines.count, 1))
            return lines.enumerated().map { offset, line in
                BudgetPlanLine(
                    category: line.category,
                    monthlyLimit: offset == lines.count - 1
                        ? max(0, total - even * Double(lines.count - 1))
                        : (even * 100).rounded() / 100,
                    color: line.color
                )
            }
        }
        var assigned = 0.0
        return lines.enumerated().map { offset, line in
            let scaled = total * (line.monthlyLimit / currentTotal)
            let limit = offset == lines.count - 1
                ? max(0, total - assigned)
                : (scaled * 100).rounded() / 100
            assigned += limit
            return BudgetPlanLine(category: line.category, monthlyLimit: limit, color: line.color)
        }
    }

    static func cacheKey(
        referenceDate: Date,
        transactionCount: Int,
        budgets: [Budget],
        calendar: Calendar = .current
    ) -> String {
        let month = BudgetSpendIndex.monthKey(from: referenceDate, calendar: calendar)
        let budgetKey = budgets.map { "\($0.id.uuidString):\($0.monthlyLimit)" }.joined(separator: "|")
        return "\(month)-\(transactionCount)-\(budgetKey)"
    }

    static func isInMonth(
        dateString: String,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date = parseDate(dateString, calendar: calendar) else { return false }
        let ref = calendar.dateComponents([.year, .month], from: referenceDate)
        let txn = calendar.dateComponents([.year, .month], from: date)
        return ref.year == txn.year && ref.month == txn.month
    }

    static func spentAmount(
        transactions: [Transaction],
        category: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        transactions
            .filter {
                $0.category == category &&
                isInMonth(dateString: $0.date, referenceDate: referenceDate, calendar: calendar) &&
                !$0.excludedFromBudget &&
                !excludedCategories.contains($0.category)
            }
            .reduce(0) { $0 + $1.amount }
    }

    static let projectionMonthCount = 6

    /// Linear pace projection for the current month (legacy; prefer `averageMonthlySpend` in UI).
    static func projectedMonthlySpend(
        spent: Double,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let day = calendar.component(.day, from: referenceDate)
        let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30
        guard day > 0 else { return spent }
        return spent / Double(day) * Double(daysInMonth)
    }

    static func startOfMonth(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// Mean category spend across the last `monthCount` calendar months ending at `referenceDate`.
    static func averageMonthlySpend(
        transactions: [Transaction],
        category: String,
        referenceDate: Date = Date(),
        monthCount: Int = projectionMonthCount,
        calendar: Calendar = .current
    ) -> Double {
        guard monthCount > 0 else { return 0 }
        let anchor = startOfMonth(referenceDate, calendar: calendar)
        var monthlyTotals: [Double] = []
        for offset in 0..<monthCount {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            monthlyTotals.append(
                spentAmount(
                    transactions: transactions,
                    category: category,
                    referenceDate: month,
                    calendar: calendar
                )
            )
        }
        guard !monthlyTotals.isEmpty else { return 0 }
        return monthlyTotals.reduce(0, +) / Double(monthlyTotals.count)
    }

    static func progressRows(
        budgets: [Budget],
        transactions: [Transaction],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetProgress] {
        let index = BudgetSpendIndex(transactions: transactions, calendar: calendar)
        return monthRows(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        ).map(\.progress)
    }

    static func totalBudgetUsedPercent(_ rows: [BudgetProgress]) -> Double {
        let limit = rows.reduce(0) { $0 + $1.monthlyLimit }
        let spent = rows.reduce(0) { $0 + $1.spent }
        guard limit > 0 else { return 0 }
        return min(spent / limit, 1.0)
    }

    static func transactionsForCategory(
        transactions: [Transaction],
        category: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        includeExcludedFromBudget: Bool = false
    ) -> [Transaction] {
        transactions
            .filter {
                $0.category == category &&
                isInMonth(dateString: $0.date, referenceDate: referenceDate, calendar: calendar) &&
                (includeExcludedFromBudget || !$0.excludedFromBudget)
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.amount > rhs.amount
                }
                return lhs.date > rhs.date
            }
    }

    static func totalSpent(_ rows: [BudgetProgress]) -> Double {
        rows.reduce(0) { $0 + $1.spent }
    }

    /// Sum of amounts shown in the budget spending list (matches pie center total).
    static func monthSpendingDisplayTotal(rows: [BudgetMonthRow]) -> Double {
        rows.reduce(0) { $0 + $1.progress.listDisplaySpent }
    }

    static func monthSpendingDisplayTotal(progress: [BudgetProgress]) -> Double {
        progress.reduce(0) { $0 + $1.listDisplaySpent }
    }

    static func recentMerchantSummary(
        transactions: [Transaction],
        category: String,
        referenceDate: Date = Date(),
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> String {
        let names = transactions
            .filter {
                $0.category == category &&
                isInMonth(dateString: $0.date, referenceDate: referenceDate, calendar: calendar) &&
                !$0.excludedFromBudget &&
                !excludedCategories.contains($0.category)
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { FinanceFormatting.displayName(for: $0) }
        return names.joined(separator: ", ")
    }

    private static func parseDate(_ value: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

enum FinanceFormatting {
    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    static func displayName(for transaction: Transaction) -> String {
        transaction.merchantName?.isEmpty == false ? transaction.merchantName! : transaction.name
    }

    static func accountLabel(_ account: Account) -> String {
        if let mask = account.mask, !mask.isEmpty {
            return "\(account.name) ••••\(mask)"
        }
        return account.name
    }
}
