import Foundation

enum NetWorthTimeRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case tenYears = "10Y"
    case all = "ALL"

    var id: String { rawValue }

    func cutoffDate(before end: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: end)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: end)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: end)
        case .fiveYears:
            return calendar.date(byAdding: .year, value: -5, to: end)
        case .tenYears:
            return calendar.date(byAdding: .year, value: -10, to: end)
        case .all:
            return nil
        }
    }
}

struct NetWorthChartPoint: Identifiable, Equatable {
    var id: String { dateString }
    let date: Date
    let dateString: String
    let netWorth: Double
    let totalAssets: Double
    let totalLiabilities: Double
}

struct NetWorthAccountRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let balance: Double
}

struct NetWorthAccountGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let total: Double
    let accounts: [NetWorthAccountRow]
}

enum NetWorthHistoryEngine {
    static func chartPoints(
        snapshots: [NetWorthSnapshot],
        accounts: [Account] = [],
        accountSnapshots: [AccountBalanceSnapshot] = [],
        transactions: [Transaction] = [],
        currentAssets: Double,
        currentLiabilities: Double,
        currentNetWorth: Double,
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .all,
        calendar: Calendar = .current
    ) -> [NetWorthChartPoint] {
        var accountByDate: [String: NetWorthChartPoint] = [:]
        if !accounts.isEmpty {
            for point in chartPointsFromAccountHistory(
                accounts: accounts,
                accountSnapshots: accountSnapshots,
                transactions: transactions,
                referenceDate: referenceDate,
                range: range,
                calendar: calendar
            ) {
                accountByDate[point.dateString] = point
            }
        }

        var byDate = accountByDate

        for snapshot in snapshots {
            guard let date = parseDate(snapshot.date, calendar: calendar) else { continue }
            let snapshotPoint = NetWorthChartPoint(
                date: date,
                dateString: snapshot.date,
                netWorth: snapshot.netWorth,
                totalAssets: snapshot.totalAssets,
                totalLiabilities: snapshot.totalLiabilities
            )
            let previous = previousPoint(before: snapshot.date, in: byDate)
            let next = nextPoint(after: snapshot.date, in: byDate)
            let estimate = accountByDate[snapshot.date]

            if shouldTrustSnapshot(
                snapshotPoint,
                estimate: estimate,
                previous: previous,
                next: next
            ) {
                byDate[snapshot.date] = snapshotPoint
            }
        }

        let todayString = formatDate(referenceDate, calendar: calendar)
        byDate[todayString] = NetWorthChartPoint(
            date: startOfDay(referenceDate, calendar: calendar),
            dateString: todayString,
            netWorth: currentNetWorth,
            totalAssets: currentAssets,
            totalLiabilities: currentLiabilities
        )

        var points = byDate.values.sorted { $0.date < $1.date }
        points = smoothIsolatedOutliers(points)
        if let cutoff = range.cutoffDate(before: referenceDate, calendar: calendar) {
            points = points.filter { $0.date >= cutoff }
        }
        return points
    }

    /// Daily net worth from per-account balances (snapshots + transaction reconstruction).
    static func chartPointsFromAccountHistory(
        accounts: [Account],
        accountSnapshots: [AccountBalanceSnapshot],
        transactions: [Transaction],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [NetWorthChartPoint] {
        guard !accounts.isEmpty else { return [] }

        let anchor = startOfDay(referenceDate, calendar: calendar)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -AccountBalanceHistoryEngine.historyMonthCount, to: anchor)
            ?? anchor

        let sparseBalances = accounts.map { account in
            var balances = AccountBalanceHistoryEngine.rawDailyBalances(
                account: account,
                snapshots: accountSnapshots,
                transactions: transactions,
                referenceDate: referenceDate,
                range: range,
                calendar: calendar
            )
            backfillLeadingBalances(
                balances: &balances,
                startDate: startDate,
                calendar: calendar
            )
            return balances
        }

        var lastBalanceByAccount = Array<Double?>(repeating: nil, count: accounts.count)
        var totalsByDate: [String: (assets: Double, liabilities: Double)] = [:]
        var day = startOfDay(startDate, calendar: calendar)

        while day <= anchor {
            let dateString = formatDate(day, calendar: calendar)
            var assets = 0.0
            var liabilities = 0.0
            var hasAnyBalance = false

            for index in accounts.indices {
                if let balance = sparseBalances[index][dateString] {
                    lastBalanceByAccount[index] = balance
                }
                guard let rawBalance = lastBalanceByAccount[index] else { continue }
                hasAnyBalance = true
                let split = NetWorthCalculator.contribution(
                    accountType: accounts[index].type,
                    balance: rawBalance
                )
                assets += split.assets
                liabilities += split.liabilities
            }

            if hasAnyBalance {
                totalsByDate[dateString] = (assets, liabilities)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return totalsByDate.compactMap { dateString, totals in
            guard let date = parseDate(dateString, calendar: calendar) else { return nil }
            return NetWorthChartPoint(
                date: date,
                dateString: dateString,
                netWorth: totals.assets - totals.liabilities,
                totalAssets: totals.assets,
                totalLiabilities: totals.liabilities
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Legacy entry point for tests and callers without account history inputs.
    static func chartPoints(
        snapshots: [NetWorthSnapshot],
        currentAssets: Double,
        currentLiabilities: Double,
        currentNetWorth: Double,
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .all,
        calendar: Calendar = .current
    ) -> [NetWorthChartPoint] {
        chartPoints(
            snapshots: snapshots,
            accounts: [],
            accountSnapshots: [],
            transactions: [],
            currentAssets: currentAssets,
            currentLiabilities: currentLiabilities,
            currentNetWorth: currentNetWorth,
            referenceDate: referenceDate,
            range: range,
            calendar: calendar
        )
    }

    static func nearestPoint(
        to date: Date,
        in points: [NetWorthChartPoint],
        calendar: Calendar = .current
    ) -> NetWorthChartPoint? {
        guard !points.isEmpty else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    static func changeFromStart(
        selected: NetWorthChartPoint,
        series: [NetWorthChartPoint]
    ) -> (amount: Double, percent: Double)? {
        guard let first = series.first, first.netWorth != 0 else {
            guard let first = series.first else { return nil }
            let amount = selected.netWorth - first.netWorth
            return amount == 0 ? nil : (amount, 0)
        }
        let amount = selected.netWorth - first.netWorth
        let percent = amount / abs(first.netWorth) * 100
        return (amount, percent)
    }

    static func accountGroups(from accounts: [Account]) -> [NetWorthAccountGroup] {
        var cash: [NetWorthAccountRow] = []
        var investments: [NetWorthAccountRow] = []
        var loans: [NetWorthAccountRow] = []
        var other: [NetWorthAccountRow] = []

        for account in accounts {
            let balance = account.currentBalance ?? 0
            let row = NetWorthAccountRow(
                id: account.id,
                name: FinanceFormatting.accountLabel(account),
                balance: balance
            )
            switch account.type.lowercased() {
            case "depository":
                cash.append(row)
            case "investment", "brokerage":
                investments.append(row)
            case "credit", "loan":
                loans.append(row)
            default:
                other.append(row)
            }
        }

        var groups: [NetWorthAccountGroup] = []
        if !cash.isEmpty {
            groups.append(group(title: "Cash", accounts: cash, liabilities: false))
        }
        if !investments.isEmpty {
            groups.append(group(title: "Investments", accounts: investments, liabilities: false))
        }
        if !loans.isEmpty {
            groups.append(group(title: "Loan", accounts: loans, liabilities: true))
        }
        if !other.isEmpty {
            groups.append(group(title: "Other", accounts: other, liabilities: false))
        }
        return groups
    }

    private static func group(
        title: String,
        accounts: [NetWorthAccountRow],
        liabilities: Bool
    ) -> NetWorthAccountGroup {
        let total = accounts.reduce(0) { partial, row in
            liabilities ? partial - abs(row.balance) : partial + row.balance
        }
        return NetWorthAccountGroup(title: title, total: total, accounts: accounts)
    }

    private static func parseDate(_ value: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func formatDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Before the first observed balance, assume the account held that balance (avoids partial-net-worth ramps).
    static func backfillLeadingBalances(
        balances: inout [String: Double],
        startDate: Date,
        calendar: Calendar
    ) {
        guard let firstKey = balances.keys.sorted().first,
              let firstDate = parseDate(firstKey, calendar: calendar),
              let firstBalance = balances[firstKey] else { return }

        var day = startOfDay(startDate, calendar: calendar)
        let firstDay = startOfDay(firstDate, calendar: calendar)
        while day < firstDay {
            let key = formatDate(day, calendar: calendar)
            if balances[key] == nil {
                balances[key] = firstBalance
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }

    static func smoothIsolatedOutliers(
        _ points: [NetWorthChartPoint],
        toleranceRatio: Double = 0.28
    ) -> [NetWorthChartPoint] {
        guard points.count >= 3 else { return points }
        var adjusted = points
        for index in 1..<(points.count - 1) {
            let previous = adjusted[index - 1].netWorth
            let current = adjusted[index].netWorth
            let next = adjusted[index + 1].netWorth
            let baseline = (previous + next) / 2
            guard baseline > 0 else { continue }

            let currentDeviation = abs(current - baseline) / baseline
            let neighborDeviation = abs(previous - next) / max(abs(previous), abs(next), 1)
            guard currentDeviation > toleranceRatio, neighborDeviation < toleranceRatio / 2 else { continue }

            let row = adjusted[index]
            adjusted[index] = NetWorthChartPoint(
                date: row.date,
                dateString: row.dateString,
                netWorth: baseline,
                totalAssets: row.totalAssets,
                totalLiabilities: row.totalLiabilities
            )
        }
        return adjusted
    }

    static func shouldTrustSnapshot(
        _ snapshot: NetWorthChartPoint,
        estimate: NetWorthChartPoint?,
        previous: NetWorthChartPoint?,
        next: NetWorthChartPoint?
    ) -> Bool {
        if let estimate {
            let base = max(abs(estimate.netWorth), 1)
            let ratio = snapshot.netWorth / base
            if ratio >= 0.75 && ratio <= 1.25 { return true }
            if ratio > 1.5 { return true }
        }

        if let previous, let next {
            let baseline = (previous.netWorth + next.netWorth) / 2
            guard baseline > 0 else { return estimate == nil }
            let snapshotDeviation = abs(snapshot.netWorth - baseline) / baseline
            let neighborDeviation = abs(previous.netWorth - next.netWorth) / baseline
            if snapshot.netWorth < baseline * 0.70,
               snapshotDeviation > 0.30,
               neighborDeviation < 0.15 {
                return false
            }
        }

        return estimate == nil
    }

    private static func previousPoint(
        before dateString: String,
        in points: [String: NetWorthChartPoint]
    ) -> NetWorthChartPoint? {
        points.keys.sorted().last { $0 < dateString }.flatMap { points[$0] }
    }

    private static func nextPoint(
        after dateString: String,
        in points: [String: NetWorthChartPoint]
    ) -> NetWorthChartPoint? {
        points.keys.sorted().first { $0 > dateString }.flatMap { points[$0] }
    }
}
