import Foundation

struct CashFlowDay: Identifiable, Equatable {
    var id: String { date }
    let date: String
    let inflow: Double
    let outflow: Double

    var net: Double { inflow - outflow }
}

enum CashFlowEngine {
    static func projectedDays(
        transactions: [Transaction],
        horizonDays: Int = 90,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [CashFlowDay] {
        let recurringOut = averageMonthlyOutflow(transactions: transactions, calendar: calendar) / 30.0
        let recurringIn = averageMonthlyInflow(transactions: transactions, calendar: calendar) / 30.0

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<horizonDays).compactMap { offset -> CashFlowDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: referenceDate) else { return nil }
            let date = formatter.string(from: day)
            let scheduled = scheduledFlow(on: day, transactions: transactions, calendar: calendar)
            return CashFlowDay(
                date: date,
                inflow: scheduled.inflow + (offset % 30 == 0 ? recurringIn * 30 : 0),
                outflow: scheduled.outflow + recurringOut
            )
        }
    }

    static func horizonTotals(days: [CashFlowDay], first: Int) -> (inflow: Double, outflow: Double, net: Double) {
        let slice = Array(days.prefix(first))
        let inflow = slice.reduce(0) { $0 + $1.inflow }
        let outflow = slice.reduce(0) { $0 + $1.outflow }
        return (inflow, outflow, inflow - outflow)
    }

    private static func averageMonthlyOutflow(transactions: [Transaction], calendar: Calendar) -> Double {
        let spend = transactions.filter {
            !BudgetMath.excludedCategories.contains($0.category) && $0.amount > 0
        }
        return monthlyAverage(spend, calendar: calendar)
    }

    private static func averageMonthlyInflow(transactions: [Transaction], calendar: Calendar) -> Double {
        let income = transactions.filter { $0.category == "Income" || $0.amount < 0 }
        return monthlyAverage(income.map { txn in
            var copy = txn
            copy.amount = abs(txn.amount)
            return copy
        }, calendar: calendar)
    }

    private static func monthlyAverage(_ transactions: [Transaction], calendar: Calendar) -> Double {
        guard !transactions.isEmpty else { return 0 }
        let total = transactions.reduce(0) { $0 + abs($1.amount) }
        return total / 3.0
    }

    private static func scheduledFlow(
        on date: Date,
        transactions: [Transaction],
        calendar: Calendar
    ) -> (inflow: Double, outflow: Double) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)

        let sameDay = transactions.filter { $0.date == key }
        let inflow = sameDay.filter { $0.category == "Income" || $0.amount < 0 }
            .reduce(0) { $0 + abs($1.amount) }
        let outflow = sameDay.filter { $0.amount > 0 && $0.category != "Income" }
            .reduce(0) { $0 + abs($1.amount) }
        return (inflow, outflow)
    }
}

struct SubscriptionCharge: Identifiable, Equatable {
    var id: String { merchant }
    let merchant: String
    let monthlyAmount: Double
    let chargeCount: Int
    let lastDate: String
}

enum SubscriptionAuditEngine {
    static let defaultLookbackDays = 120

    static func recurringCharges(transactions: [Transaction], lookbackDays: Int = defaultLookbackDays) -> [SubscriptionCharge] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let candidates = transactions.filter { txn in
            let isSubscriptionCategory = txn.category == "Subscriptions"
            let name = FinanceFormatting.displayName(for: txn).lowercased()
            let looksRecurring = name.contains("subscription") || name.contains("netflix") || name.contains("spotify")
            guard isSubscriptionCategory || looksRecurring else { return false }
            guard let date = formatter.date(from: txn.date) else { return false }
            return date >= cutoff && txn.amount > 0
        }

        let grouped = Dictionary(grouping: candidates) {
            FinanceFormatting.displayName(for: $0).lowercased()
        }

        return grouped.map { merchant, txns in
            let total = txns.reduce(0) { $0 + abs($1.amount) }
            let months = max(Double(Set(txns.map { String($0.date.prefix(7)) }).count), 1)
            return SubscriptionCharge(
                merchant: merchant.capitalized,
                monthlyAmount: total / months,
                chargeCount: txns.count,
                lastDate: txns.map(\.date).max() ?? ""
            )
        }
        .sorted { $0.monthlyAmount > $1.monthlyAmount }
    }

    static func totalMonthlySpend(_ charges: [SubscriptionCharge]) -> Double {
        charges.reduce(0) { $0 + $1.monthlyAmount }
    }
}

enum BudgetAlertEngine {
    static func alerts(
        progress: [BudgetProgress],
        threshold: Double = 0.8
    ) -> [String] {
        progress.compactMap { row in
            if row.isOverBudget {
                return "\(row.category) is over budget."
            }
            if row.percentUsed >= threshold {
                return "\(row.category) has used \(Int(row.percentUsed * 100))% of its budget."
            }
            return nil
        }
    }
}
