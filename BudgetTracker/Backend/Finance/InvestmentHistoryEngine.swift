import Foundation

enum InvestmentHistoryEngine {
    /// Security trades convert cash ↔ holdings and do not change total account value.
    static func affectsTotalValue(type: String?, subtype: String?) -> Bool {
        let type = (type ?? "").lowercased()
        let subtype = (subtype ?? "").lowercased()
        if type == "buy" || type == "sell" || type == "cancel" {
            return false
        }
        if subtype == "buy" || subtype == "sell" || subtype.contains("reinvest") {
            return false
        }
        return true
    }

    static func chartPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        range: NetWorthTimeRange = .oneYear,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        mergedDailyPoints(
            account: account,
            snapshots: snapshots,
            transactions: transactions,
            cashTransactions: cashTransactions,
            referenceDate: referenceDate,
            range: range,
            calendar: calendar
        )
    }

    /// Snapshots are market marks and forward-fill. Cash/NAV flows jump between them.
    /// With no snapshots, walk back from today's live value using those flows only.
    static func mergedDailyPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        var snapshotByDate: [String: Double] = [:]
        for snapshot in snapshots where snapshot.accountId == account.id {
            guard let balance = snapshot.currentBalance else { continue }
            snapshotByDate[snapshot.date] = balance
        }

        if snapshotByDate.isEmpty {
            return reconstructedDailyPoints(
                account: account,
                transactions: transactions,
                cashTransactions: cashTransactions,
                referenceDate: referenceDate,
                range: range,
                calendar: calendar
            )
        }

        var amountByDate: [String: Double] = [:]
        for txn in transactions where txn.accountId == account.id
            && affectsTotalValue(type: txn.type, subtype: txn.subtype)
        {
            amountByDate[txn.date, default: 0] += txn.amount
        }
        for txn in cashTransactions where txn.accountId == account.id && !txn.pending {
            amountByDate[txn.date, default: 0] += txn.amount
        }

        let anchor = calendar.startOfDay(for: referenceDate)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -AccountBalanceHistoryEngine.historyMonthCount, to: anchor)
            ?? anchor
        guard let firstDateString = snapshotByDate.keys.sorted().first,
              let firstBalance = snapshotByDate[firstDateString],
              var day = parseDate(firstDateString, calendar: calendar)
        else {
            return reconstructedDailyPoints(
                account: account,
                transactions: transactions,
                cashTransactions: cashTransactions,
                referenceDate: referenceDate,
                range: range,
                calendar: calendar
            )
        }

        let todayString = formatDate(anchor, calendar: calendar)
        var merged: [String: AccountBalancePoint] = [:]
        var running = firstBalance
        while day <= anchor {
            let dateString = formatDate(day, calendar: calendar)
            let source: AccountBalancePoint.Source
            if dateString == todayString, let current = account.currentBalance {
                running = current
                source = .snapshot
            } else if let snap = snapshotByDate[dateString] {
                running = snap
                source = .snapshot
            } else {
                running -= amountByDate[dateString, default: 0]
                source = .reconstructed
            }
            merged[dateString] = AccountBalancePoint(
                date: day,
                dateString: dateString,
                balance: running,
                source: source
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        running = firstBalance
        day = parseDate(firstDateString, calendar: calendar) ?? day
        let start = calendar.startOfDay(for: startDate)
        while day > start {
            running += amountByDate[formatDate(day, calendar: calendar), default: 0]
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            let dateString = formatDate(day, calendar: calendar)
            merged[dateString] = AccountBalancePoint(
                date: day,
                dateString: dateString,
                balance: running,
                source: .reconstructed
            )
        }

        var points = merged.values.sorted { $0.date < $1.date }
        if let cutoff = range.cutoffDate(before: referenceDate, calendar: calendar) {
            points = points.filter { $0.date >= cutoff }
        }
        return points
    }

    static func reconstructedDailyPoints(
        account: Account,
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        guard let current = account.currentBalance else { return [] }

        let anchor = calendar.startOfDay(for: referenceDate)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -AccountBalanceHistoryEngine.historyMonthCount, to: anchor)
            ?? anchor

        var amountByDate: [String: Double] = [:]
        for txn in transactions where txn.accountId == account.id && affectsTotalValue(type: txn.type, subtype: txn.subtype) {
            amountByDate[txn.date, default: 0] += txn.amount
        }
        for txn in cashTransactions where txn.accountId == account.id && !txn.pending {
            amountByDate[txn.date, default: 0] += txn.amount
        }

        let startString = formatDate(calendar.startOfDay(for: startDate), calendar: calendar)
        let referenceString = formatDate(anchor, calendar: calendar)
        var futureSum = amountByDate
            .filter { $0.key > startString && $0.key <= referenceString }
            .reduce(0) { $0 + $1.value }

        var points: [AccountBalancePoint] = []
        var day = calendar.startOfDay(for: startDate)

        while day <= anchor {
            let dateString = formatDate(day, calendar: calendar)
            let balance = current + futureSum
            points.append(
                AccountBalancePoint(
                    date: day,
                    dateString: dateString,
                    balance: balance,
                    source: .reconstructed
                )
            )
            if let next = calendar.date(byAdding: .day, value: 1, to: day) {
                futureSum -= amountByDate[formatDate(next, calendar: calendar), default: 0]
                day = next
            } else {
                break
            }
        }

        return points
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
}
