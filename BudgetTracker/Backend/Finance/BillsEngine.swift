import Foundation

struct BillItem: Identifiable, Equatable {
    var id: UUID { transactionId }
    let transactionId: UUID
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
        transactions: [Transaction],
        budgets: [Budget] = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BillItem] {
        let anchors = transactions.filter(\.isFixedBill)
        let items = anchors.map { anchor in
            billItem(
                anchor: anchor,
                transactions: transactions,
                budgets: budgets,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        return items.sorted { $0.dueDay < $1.dueDay }
    }

    static func daysWithBills(_ bills: [BillItem]) -> Set<Int> {
        Set(bills.map(\.dueDay))
    }

    static func anchor(for billId: UUID, transactions: [Transaction]) -> Transaction? {
        transactions.first { $0.id == billId && $0.isFixedBill }
    }

    private static func billItem(
        anchor: Transaction,
        transactions: [Transaction],
        budgets: [Budget],
        referenceDate: Date,
        calendar: Calendar
    ) -> BillItem {
        let name = displayName(for: anchor)
        let dueDay = resolvedDueDay(for: anchor, transactions: transactions, calendar: calendar)
        let dueDate = dueDateString(day: dueDay, referenceDate: referenceDate, calendar: calendar)
        let amount = resolvedAmount(for: anchor)
        let spent = merchantSpendThisMonth(
            anchor: anchor,
            transactions: transactions,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let isPaid = spent >= amount * 0.85
        let color = budgets.first(where: { $0.category == anchor.category })?.color
            ?? BudgetPalette.color(forCategory: anchor.category)
        return BillItem(
            transactionId: anchor.id,
            name: name,
            category: anchor.category,
            dueDate: dueDate,
            dueDay: dueDay,
            displayDue: displayDueLabel(dueDate: dueDate, calendar: calendar),
            amount: amount,
            isPaid: isPaid,
            color: color
        )
    }

    static func displayName(for transaction: Transaction) -> String {
        let nickname = transaction.billNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nickname.isEmpty { return nickname }
        return FinanceFormatting.displayName(for: transaction)
    }

    static func resolvedDueDay(
        for anchor: Transaction,
        transactions: [Transaction],
        calendar: Calendar = .current
    ) -> Int {
        if let day = anchor.billDueDay, (1...31).contains(day) {
            return day
        }
        return typicalDueDay(anchor: anchor, transactions: transactions, calendar: calendar)
    }

    static func resolvedAmount(for anchor: Transaction) -> Double {
        if let amount = anchor.billAmount, amount > 0 {
            return amount
        }
        return abs(anchor.amount)
    }

    static func defaultDueDay(for transaction: Transaction, calendar: Calendar = .current) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: transaction.date) else { return 1 }
        return calendar.component(.day, from: date)
    }

    private static func typicalDueDay(
        anchor: Transaction,
        transactions: [Transaction],
        calendar: Calendar
    ) -> Int {
        let pattern = MerchantRulePattern.from(transaction: anchor)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let days = transactions
            .filter { matchesMerchant($0, pattern: pattern) && $0.amount > 0 }
            .compactMap { txn -> Int? in
                guard let date = formatter.date(from: txn.date) else { return nil }
                return calendar.component(.day, from: date)
            }
        guard !days.isEmpty else {
            return defaultDueDay(for: anchor, calendar: calendar)
        }
        var counts: [Int: Int] = [:]
        for day in days { counts[day, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? defaultDueDay(for: anchor, calendar: calendar)
    }

    private static func merchantSpendThisMonth(
        anchor: Transaction,
        transactions: [Transaction],
        referenceDate: Date,
        calendar: Calendar
    ) -> Double {
        let pattern = MerchantRulePattern.from(transaction: anchor)
        return transactions
            .filter {
                matchesMerchant($0, pattern: pattern) &&
                BudgetMath.isInMonth(dateString: $0.date, referenceDate: referenceDate, calendar: calendar) &&
                $0.amount > 0
            }
            .reduce(0) { $0 + $1.amount }
    }

    private static func matchesMerchant(_ transaction: Transaction, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        let haystack = MerchantRulePattern.from(transaction: transaction)
        return haystack.contains(pattern) || pattern.contains(haystack)
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
