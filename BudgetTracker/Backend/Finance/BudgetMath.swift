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
}

enum BudgetMath {
    static let excludedCategories: Set<String> = ["Income", "Transfers"]

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
                !excludedCategories.contains($0.category)
            }
            .reduce(0) { $0 + abs($1.amount) }
    }

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

    static func progressRows(
        budgets: [Budget],
        transactions: [Transaction],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetProgress] {
        budgets.map { budget in
            let spent = spentAmount(
                transactions: transactions,
                category: budget.category,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let projected = budget.isFixed
                ? spent
                : projectedMonthlySpend(spent: spent, referenceDate: referenceDate, calendar: calendar)
            return BudgetProgress(
                category: budget.category,
                monthlyLimit: budget.monthlyLimit,
                spent: spent,
                projectedSpend: projected,
                isFixed: budget.isFixed,
                isRollover: budget.isRollover,
                color: budget.color
            )
        }
        .sorted { $0.category < $1.category }
    }

    static func totalBudgetUsedPercent(_ rows: [BudgetProgress]) -> Double {
        let limit = rows.reduce(0) { $0 + $1.monthlyLimit }
        let spent = rows.reduce(0) { $0 + $1.spent }
        guard limit > 0 else { return 0 }
        return min(spent / limit, 1.0)
    }

    static func totalSpent(_ rows: [BudgetProgress]) -> Double {
        rows.reduce(0) { $0 + $1.spent }
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
