import Foundation

enum InvestmentHistoryEngine {
    static func chartPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [InvestmentTransaction],
        range: NetWorthTimeRange = .oneYear,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        let accountSnapshots = snapshots
            .filter { $0.accountId == account.id }
            .compactMap { snapshot -> AccountBalancePoint? in
                guard let date = parseDate(snapshot.date, calendar: calendar),
                      let balance = snapshot.currentBalance else { return nil }
                return AccountBalancePoint(
                    date: date,
                    dateString: snapshot.date,
                    balance: balance,
                    source: .snapshot
                )
            }

        let reconstructed = reconstructedDailyPoints(
            account: account,
            transactions: transactions,
            referenceDate: referenceDate,
            range: range,
            calendar: calendar
        )

        var merged: [String: AccountBalancePoint] = [:]
        for point in reconstructed {
            merged[point.dateString] = point
        }
        for point in accountSnapshots {
            merged[point.dateString] = point
        }
        applyTodayLiveBalance(
            account: account,
            referenceDate: referenceDate,
            calendar: calendar,
            merged: &merged
        )

        var points = merged.values.sorted { $0.date < $1.date }
        if let cutoff = range.cutoffDate(before: referenceDate, calendar: calendar) {
            points = points.filter { $0.date >= cutoff }
        }
        return points
    }

    static func reconstructedDailyPoints(
        account: Account,
        transactions: [InvestmentTransaction],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        guard let current = account.currentBalance else { return [] }

        let anchor = calendar.startOfDay(for: referenceDate)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -AccountBalanceHistoryEngine.historyMonthCount, to: anchor)
            ?? anchor

        let accountTxns = transactions
            .filter { $0.accountId == account.id }
            .sorted { $0.date < $1.date }

        var amountByDate: [String: Double] = [:]
        for txn in accountTxns {
            amountByDate[txn.date, default: 0] += txn.amount
        }

        let startString = formatDate(calendar.startOfDay(for: startDate), calendar: calendar)
        let referenceString = formatDate(anchor, calendar: calendar)
        var futureSum = accountTxns
            .filter { $0.date > startString && $0.date <= referenceString }
            .reduce(0) { $0 + $1.amount }

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

    private static func applyTodayLiveBalance(
        account: Account,
        referenceDate: Date,
        calendar: Calendar,
        merged: inout [String: AccountBalancePoint]
    ) {
        guard let current = account.currentBalance else { return }
        let day = calendar.startOfDay(for: referenceDate)
        let todayString = formatDate(day, calendar: calendar)
        merged[todayString] = AccountBalancePoint(
            date: day,
            dateString: todayString,
            balance: current,
            source: .snapshot
        )
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
