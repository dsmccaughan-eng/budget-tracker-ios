import XCTest
@testable import BudgetTracker

final class TransactionMonthGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func txn(date: String) -> Transaction {
        Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: 10,
            date: date,
            merchantName: "Shop",
            name: "Shop",
            category: "Shopping",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
    }

    func testGroupsByMonthNewestFirst() {
        let groups = TransactionMonthGrouping.groups(
            from: [
                txn(date: "2026-03-10"),
                txn(date: "2026-02-01"),
                txn(date: "2026-03-01")
            ],
            calendar: calendar
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].monthKey, "2026-03")
        XCTAssertEqual(groups[0].transactions.map(\.date), ["2026-03-10", "2026-03-01"])
        XCTAssertEqual(groups[1].monthKey, "2026-02")
    }
}
