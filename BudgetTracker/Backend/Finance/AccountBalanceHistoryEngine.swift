import Foundation

struct AccountBalanceSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var accountId: UUID
    var date: String
    var currentBalance: Double?
    var availableBalance: Double?

    enum CodingKeys: String, CodingKey {
        case id, date
        case accountId = "account_id"
        case currentBalance = "current_balance"
        case availableBalance = "available_balance"
    }
}

struct AccountBalancePoint: Identifiable, Equatable {
    var id: String { dateString }
    let date: Date
    let dateString: String
    let balance: Double
    let source: Source

    enum Source: Equatable {
        case snapshot
        case reconstructed
    }
}

enum AccountBalanceHistoryEngine {
    static let historyMonthCount = 12

    static func displayBalance(_ balance: Double, accountType: String) -> Double {
        switch accountType.lowercased() {
        case "credit", "loan":
            return -abs(balance)
        default:
            return balance
        }
    }

    static func historyPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [Transaction],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
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
                    balance: displayBalance(balance, accountType: account.type),
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

        var points = merged.values.sorted { $0.date < $1.date }
        if let cutoff = range.cutoffDate(before: referenceDate, calendar: calendar) {
            points = points.filter { $0.date >= cutoff }
        }
        return points
    }

    /// Plaid: positive amounts are outflows. Balance at end of day D =
    /// current balance + sum(amount) for settled transactions after D.
    static func reconstructedDailyPoints(
        account: Account,
        transactions: [Transaction],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        guard let current = account.currentBalance else { return [] }

        let anchor = calendar.startOfDay(for: referenceDate)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -historyMonthCount, to: anchor)
            ?? anchor

        let accountTxns = transactions
            .filter { $0.accountId == account.id && !$0.pending }
            .sorted { $0.date < $1.date }

        var points: [AccountBalancePoint] = []
        var day = calendar.startOfDay(for: startDate)
        let end = anchor

        while day <= end {
            let dateString = formatDate(day, calendar: calendar)
            let balance = balanceAtEndOfDay(
                day: day,
                currentBalance: current,
                referenceDay: anchor,
                transactions: accountTxns,
                calendar: calendar
            )
            points.append(
                AccountBalancePoint(
                    date: day,
                    dateString: dateString,
                    balance: displayBalance(balance, accountType: account.type),
                    source: .reconstructed
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return points
    }

    static func balanceAtEndOfDay(
        day: Date,
        currentBalance: Double,
        referenceDay: Date,
        transactions: [Transaction],
        calendar: Calendar = .current
    ) -> Double {
        let dayString = formatDate(day, calendar: calendar)
        let referenceString = formatDate(referenceDay, calendar: calendar)
        let futureAmount = transactions
            .filter { $0.date > dayString && $0.date <= referenceString }
            .reduce(0) { $0 + $1.amount }
        return currentBalance + futureAmount
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
