import Foundation

struct BillItem: Identifiable, Equatable {
    var id: String { "\(category)-\(dueDate)" }
    let name: String
    let category: String
    let dueDate: String
    let dueDay: Int
    let displayDue: String
    let amount: Double
    let isPaid: Bool
    let color: String
}

enum BillsEngine {
    static func bills(
        budgets: [Budget],
        transactions: [Transaction],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BillItem] {
        let fixed = budgets.filter(\.isFixed)
        let items = fixed.map { budget in
            let dueDay = typicalDueDay(
                category: budget.category,
                transactions: transactions,
                calendar: calendar
            )
            let dueDate = dueDateString(
                day: dueDay,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let spent = BudgetMath.spentAmount(
                transactions: transactions,
                category: budget.category,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let isPaid = spent >= budget.monthlyLimit * 0.85
            return BillItem(
                name: budget.category,
                category: budget.category,
                dueDate: dueDate,
                dueDay: dueDay,
                displayDue: displayDueLabel(dueDate: dueDate, calendar: calendar),
                amount: budget.monthlyLimit,
                isPaid: isPaid,
                color: budget.color
            )
        }
        return items.sorted { $0.dueDay < $1.dueDay }
    }

    static func daysWithBills(_ bills: [BillItem]) -> Set<Int> {
        Set(bills.map(\.dueDay))
    }

    private static func typicalDueDay(
        category: String,
        transactions: [Transaction],
        calendar: Calendar
    ) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let days = transactions
            .filter { $0.category == category && $0.amount > 0 }
            .compactMap { txn -> Int? in
                guard let date = formatter.date(from: txn.date) else { return nil }
                return calendar.component(.day, from: date)
            }
        guard !days.isEmpty else { return 1 }
        var counts: [Int: Int] = [:]
        for day in days { counts[day, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? 1
    }

    private static func dueDateString(
        day: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        var parts = calendar.dateComponents([.year, .month], from: referenceDate)
        let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 28
        parts.day = min(max(day, 1), daysInMonth)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = calendar.date(from: parts) ?? referenceDate
        return formatter.string(from: date)
    }

    private static func displayDueLabel(dueDate: String, calendar: Calendar) -> String {
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dueDate) else { return dueDate }
        let label = DateFormatter()
        label.calendar = calendar
        label.locale = Locale.current
        label.dateFormat = "EEE, MMM d"
        return label.string(from: date)
    }
}
