import Foundation

struct TransactionMonthGroup: Identifiable, Equatable {
    var id: String { monthKey }
    let monthKey: String
    let title: String
    let transactions: [Transaction]
}

enum TransactionMonthGrouping {
    static func groups(
        from transactions: [Transaction],
        calendar: Calendar = .current
    ) -> [TransactionMonthGroup] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let titleFormatter = DateFormatter()
        titleFormatter.calendar = calendar
        titleFormatter.locale = Locale.current
        titleFormatter.dateFormat = "MMMM yyyy"

        var buckets: [String: [Transaction]] = [:]
        for txn in transactions {
            guard let date = formatter.date(from: txn.date) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { continue }
            let key = String(format: "%04d-%02d", year, month)
            buckets[key, default: []].append(txn)
        }

        return buckets.keys.sorted(by: >).map { key in
            let sorted = (buckets[key] ?? []).sorted { $0.date > $1.date }
            let title: String
            if let sample = sorted.first,
               let date = formatter.date(from: sample.date) {
                title = titleFormatter.string(from: date)
            } else {
                title = key
            }
            return TransactionMonthGroup(monthKey: key, title: title, transactions: sorted)
        }
    }
}
