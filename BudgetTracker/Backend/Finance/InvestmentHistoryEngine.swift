import Foundation

enum InvestmentHistoryEngine {
    /// Security trades convert cash ↔ holdings and do not change total account value.
    static func affectsTotalValue(type: String?, subtype: String?) -> Bool {
        valueDelta(type: type, subtype: subtype, amount: 1) != nil
    }

    /// Change in account value. Inflows are always positive regardless of Plaid sign.
    static func valueDelta(type: String?, subtype: String?, amount: Double) -> Double? {
        let type = (type ?? "").lowercased()
        let subtype = (subtype ?? "").lowercased()
        if type == "buy" || type == "sell" || type == "cancel" {
            return nil
        }
        if subtype == "buy" || subtype == "sell" || subtype.contains("reinvest") {
            return nil
        }
        if isInflow(subtype: subtype) {
            return abs(amount)
        }
        if isOutflow(subtype: subtype) || type == "fee" {
            return -abs(amount)
        }
        if isIncome(subtype: subtype) {
            return abs(amount)
        }
        return -amount
    }

    static func chartPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        investmentAccounts: [Account] = [],
        range: NetWorthTimeRange = .oneYear,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        mergedDailyPoints(
            account: account,
            snapshots: snapshots,
            transactions: transactions,
            cashTransactions: cashTransactions,
            investmentAccounts: investmentAccounts,
            referenceDate: referenceDate,
            range: range,
            calendar: calendar
        )
    }

    /// Chronological money-in plus market P/L, pinned to snapshots and today's live value.
    static func mergedDailyPoints(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        investmentAccounts: [Account] = [],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        guard let current = account.currentBalance else { return [] }
        let formatter = dateFormatter(calendar: calendar)
        let anchor = calendar.startOfDay(for: referenceDate)
        let startDate = range.cutoffDate(before: anchor, calendar: calendar)
            ?? calendar.date(byAdding: .month, value: -AccountBalanceHistoryEngine.historyMonthCount, to: anchor)
            ?? anchor
        let startDay = calendar.startOfDay(for: startDate)
        let todayString = formatter.string(from: anchor)

        let deltas = netValueDeltaByDate(
            account: account,
            transactions: transactions,
            cashTransactions: cashTransactions,
            investmentAccounts: investmentAccounts
        )
        let marks = marketMarks(
            account: account,
            snapshots: snapshots,
            current: current,
            today: anchor,
            todayString: todayString,
            formatter: formatter
        )
        guard let firstMark = marks.first else { return [] }

        var pointsByDate: [String: AccountBalancePoint] = [:]
        var day = startDay
        while day <= firstMark.date {
            let dateString = formatter.string(from: day)
            let future = sumDeltas(deltas, after: dateString, through: firstMark.dateString)
            let isMark = dateString == firstMark.dateString
            pointsByDate[dateString] = AccountBalancePoint(
                date: day,
                dateString: dateString,
                balance: firstMark.balance - future,
                source: isMark ? .snapshot : .reconstructed
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for index in 0..<(marks.count - 1) {
            let startMark = marks[index]
            let endMark = marks[index + 1]
            var days: [Date] = []
            var cursor = startMark.date
            while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next <= endMark.date {
                days.append(next)
                cursor = next
            }
            let flowSum = sumDeltas(deltas, after: startMark.dateString, through: endMark.dateString)
            let market = endMark.balance - (startMark.balance + flowSum)
            let dailyMarket = days.isEmpty ? 0 : market / Double(days.count)
            var running = startMark.balance
            for step in days {
                let dateString = formatter.string(from: step)
                running += deltas[dateString, default: 0] + dailyMarket
                let isEnd = dateString == endMark.dateString
                pointsByDate[dateString] = AccountBalancePoint(
                    date: step,
                    dateString: dateString,
                    balance: isEnd ? endMark.balance : running,
                    source: isEnd ? .snapshot : .reconstructed
                )
            }
        }

        var points = pointsByDate.values.sorted { $0.date < $1.date }
        if let cutoff = range.cutoffDate(before: referenceDate, calendar: calendar) {
            points = points.filter { $0.date >= cutoff }
        }
        return points
    }

    static func reconstructedDailyPoints(
        account: Account,
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction] = [],
        investmentAccounts: [Account] = [],
        referenceDate: Date = Date(),
        range: NetWorthTimeRange = .oneYear,
        calendar: Calendar = .current
    ) -> [AccountBalancePoint] {
        mergedDailyPoints(
            account: account,
            snapshots: [],
            transactions: transactions,
            cashTransactions: cashTransactions,
            investmentAccounts: investmentAccounts,
            referenceDate: referenceDate,
            range: range,
            calendar: calendar
        )
    }

    private static func netValueDeltaByDate(
        account: Account,
        transactions: [InvestmentTransaction],
        cashTransactions: [Transaction],
        investmentAccounts: [Account]
    ) -> [String: Double] {
        var deltas: [String: Double] = [:]
        var datesWithInvestmentFlow: Set<String> = []
        for txn in transactions where txn.accountId == account.id {
            guard let delta = valueDelta(type: txn.type, subtype: txn.subtype, amount: txn.amount) else {
                continue
            }
            deltas[txn.date, default: 0] += delta
            datesWithInvestmentFlow.insert(txn.date)
        }
        for txn in cashTransactions where txn.accountId == account.id && !txn.pending {
            guard !datesWithInvestmentFlow.contains(txn.date) else { continue }
            deltas[txn.date, default: 0] += -txn.amount
            datesWithInvestmentFlow.insert(txn.date)
        }
        let peers = investmentAccounts.isEmpty ? [account] : investmentAccounts.filter {
            !AccountBalanceHistoryEngine.supportsTransactionReconstruction(accountType: $0.type)
        }
        for txn in cashTransactions {
            guard shouldInferContribution(txn, to: account, among: peers) else { continue }
            guard !datesWithInvestmentFlow.contains(txn.date) else { continue }
            deltas[txn.date, default: 0] += abs(txn.amount)
            datesWithInvestmentFlow.insert(txn.date)
        }
        return deltas
    }

    private static func shouldInferContribution(
        _ txn: Transaction,
        to account: Account,
        among: [Account]
    ) -> Bool {
        guard txn.accountId != account.id, !txn.pending, txn.amount > 0 else { return false }
        if among.contains(where: { $0.id == txn.accountId }) { return false }
        guard looksLikeInvestmentTransfer(txn) else { return false }
        if among.count <= 1 { return true }
        return nameTokens(account.name).contains { token in
            txn.name.lowercased().contains(token) || (txn.merchantName?.lowercased().contains(token) ?? false)
        }
    }

    private static func looksLikeInvestmentTransfer(_ txn: Transaction) -> Bool {
        if txn.category == "Investments" { return true }
        let haystack = "\(txn.name) \(txn.merchantName ?? "")".lowercased()
        let keywords = [
            "401k", "401(k)", "ira", "brokerage", "vanguard", "fidelity", "schwab",
            "robinhood", "betterment", "contribution"
        ]
        return keywords.contains { haystack.contains($0) }
    }

    private static func nameTokens(_ name: String) -> [String] {
        name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 4 }
    }

    private static func isInflow(subtype: String) -> Bool {
        subtype.contains("contribution")
            || subtype.contains("deposit")
            || subtype.contains("transfer in")
            || subtype.contains("transfer_in")
            || subtype.contains("rollover")
    }

    private static func isOutflow(subtype: String) -> Bool {
        subtype.contains("withdrawal")
            || subtype.contains("transfer out")
            || subtype.contains("transfer_out")
            || subtype.contains("fee")
    }

    private static func isIncome(subtype: String) -> Bool {
        subtype.contains("dividend") || subtype.contains("interest") || subtype.contains("gain")
    }

    private static func marketMarks(
        account: Account,
        snapshots: [AccountBalanceSnapshot],
        current: Double,
        today: Date,
        todayString: String,
        formatter: DateFormatter
    ) -> [(date: Date, dateString: String, balance: Double)] {
        var byDate: [String: (Date, Double)] = [:]
        for snapshot in snapshots where snapshot.accountId == account.id {
            guard let balance = snapshot.currentBalance,
                  let date = formatter.date(from: snapshot.date),
                  date <= today else { continue }
            byDate[snapshot.date] = (date, balance)
        }
        byDate[todayString] = (today, current)
        return byDate
            .map { (date: $0.value.0, dateString: $0.key, balance: $0.value.1) }
            .sorted { $0.date < $1.date }
    }

    private static func sumDeltas(_ deltas: [String: Double], after start: String, through end: String) -> Double {
        deltas.reduce(0) { partial, entry in
            guard entry.key > start, entry.key <= end else { return partial }
            return partial + entry.value
        }
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
