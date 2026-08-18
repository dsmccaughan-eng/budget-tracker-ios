import Foundation

struct BudgetMonthRow: Equatable, Identifiable {
    var id: String { progress.category }
    let progress: BudgetProgress
    let recentSummary: String
}

struct BudgetMonthSections: Equatable {
    let spending: [BudgetMonthRow]
    let income: [BudgetMonthRow]
    let transfers: [BudgetMonthRow]
}

struct BudgetPlanLine: Equatable, Identifiable {
    var id: String { category }
    let category: String
    var monthlyLimit: Double
    let color: String
}

/// Single-pass index so budget rows do not re-scan thousands of transactions per render.
struct BudgetSpendIndex {
    let transactionCount: Int
    private let spentByCategoryMonth: [String: [String: Double]]
    private let spentByCategoryDate: [String: [String: Double]]
    private let monthsWithActivity: Set<String>
    private let recentNamesByCategoryMonth: [String: [String: [String]]]

    init(transactions: [Transaction], calendar: Calendar = .current) {
        transactionCount = transactions.count
        var spent: [String: [String: Double]] = [:]
        var spentDates: [String: [String: Double]] = [:]
        var months: Set<String> = []
        var recent: [String: [String: [(date: String, name: String)]]] = [:]

        for txn in transactions {
            guard !txn.excludedFromBudget else { continue }
            let monthKey = Self.monthKey(from: txn.date)
            let dateKey = String(txn.date.prefix(10))
            months.insert(monthKey)
            spent[txn.category, default: [:]][monthKey, default: 0] += txn.amount
            spentDates[txn.category, default: [:]][dateKey, default: 0] += txn.amount
            let name = FinanceFormatting.displayName(for: txn)
            recent[txn.category, default: [:]][monthKey, default: []].append((txn.date, name))
        }

        spentByCategoryMonth = spent
        spentByCategoryDate = spentDates
        monthsWithActivity = months
        var namesByMonth: [String: [String: [String]]] = [:]
        for (category, byMonth) in recent {
            var monthNames: [String: [String]] = [:]
            for (monthKey, entries) in byMonth {
                monthNames[monthKey] = entries
                    .sorted { $0.date > $1.date }
                    .prefix(3)
                    .map(\.name)
            }
            namesByMonth[category] = monthNames
        }
        recentNamesByCategoryMonth = namesByMonth
    }

    func spent(category: String, referenceDate: Date, calendar: Calendar = .current) -> Double {
        let key = Self.monthKey(from: referenceDate, calendar: calendar)
        return spentByCategoryMonth[category]?[key] ?? 0
    }

    func averageMonthlySpend(
        category: String,
        referenceDate: Date,
        monthCount: Int = BudgetMath.projectionMonthCount,
        calendar: Calendar = .current
    ) -> Double {
        guard monthCount > 0 else { return 0 }
        let anchor = BudgetMath.startOfMonth(referenceDate, calendar: calendar)
        var total = 0.0
        for offset in 0..<monthCount {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            total += spent(category: category, referenceDate: month, calendar: calendar)
        }
        return total / Double(monthCount)
    }

    /// Average spend from day 1 through this day-of-month across the prior `monthCount` months.
    /// Months with no transactions at all are skipped so missing history is not treated as $0.
    func typicalSpendByNow(
        category: String,
        referenceDate: Date,
        monthCount: Int = BudgetMath.projectionMonthCount,
        calendar: Calendar = .current
    ) -> Double {
        typicalSamples(
            referenceDate: referenceDate,
            monthCount: monthCount,
            calendar: calendar
        ) { month, throughDay in
            spentThroughDay(
                category: category,
                monthDate: month,
                throughDay: throughDay,
                calendar: calendar
            )
        }
    }

    func spentThroughDay(
        category: String,
        monthDate: Date,
        throughDay: Int,
        calendar: Calendar = .current
    ) -> Double {
        let monthKey = Self.monthKey(from: monthDate, calendar: calendar)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? throughDay
        let cap = min(max(throughDay, 0), daysInMonth)
        guard cap > 0 else { return 0 }
        var total = 0.0
        for day in 1...cap {
            let dateString = String(format: "%@-%02d", monthKey, day)
            total += spentByCategoryDate[category]?[dateString] ?? 0
        }
        return total
    }

    func recentMerchantSummary(
        category: String,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let key = Self.monthKey(from: referenceDate, calendar: calendar)
        return (recentNamesByCategoryMonth[category]?[key] ?? []).joined(separator: ", ")
    }

    func categoriesWithActivity(referenceDate: Date, calendar: Calendar = .current) -> [String] {
        let key = Self.monthKey(from: referenceDate, calendar: calendar)
        return spentByCategoryMonth.compactMap { category, byMonth in
            guard let amount = byMonth[key], amount != 0 else { return nil }
            return category
        }
        .sorted()
    }

    func hasActivity(category: String, referenceDate: Date, calendar: Calendar = .current) -> Bool {
        spent(category: category, referenceDate: referenceDate, calendar: calendar) != 0
    }

    private func typicalSamples(
        referenceDate: Date,
        monthCount: Int,
        calendar: Calendar,
        amount: (Date, Int) -> Double
    ) -> Double {
        guard monthCount > 0 else { return 0 }
        let paceDate = BudgetMath.paceReferenceDate(referenceDate, calendar: calendar)
        let throughDay = calendar.component(.day, from: paceDate)
        let anchor = BudgetMath.startOfMonth(referenceDate, calendar: calendar)
        var samples: [Double] = []
        for offset in 1...monthCount {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            let key = Self.monthKey(from: month, calendar: calendar)
            guard monthsWithActivity.contains(key) else { continue }
            samples.append(amount(month, throughDay))
        }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    static func monthKey(from dateString: String) -> String {
        String(dateString.prefix(7))
    }

    static func monthKey(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
