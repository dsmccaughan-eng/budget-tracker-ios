import XCTest
@testable import BudgetTracker

final class BillsEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    }

    private func budget(category: String, limit: Double, isFixed: Bool) -> Budget {
        Budget(
            id: UUID(),
            category: category,
            monthlyLimit: limit,
            color: "#3B82F6",
            isRollover: false,
            isFixed: isFixed
        )
    }

    private func txn(category: String, amount: Double, date: String) -> Transaction {
        Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: amount,
            date: date,
            merchantName: "Test",
            name: "Test",
            category: category,
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
    }

    func testOnlyFixedBudgetsBecomeBills() {
        let bills = BillsEngine.bills(
            budgets: [
                budget(category: "Groceries", limit: 400, isFixed: false),
                budget(category: "Housing & Utilities", limit: 1800, isFixed: true)
            ],
            transactions: [],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills[0].category, "Housing & Utilities")
    }

    func testBillMarkedPaidWhenSpendMeetsThreshold() {
        let bills = BillsEngine.bills(
            budgets: [budget(category: "Housing & Utilities", limit: 100, isFixed: true)],
            transactions: [txn(category: "Housing & Utilities", amount: 90, date: "2026-03-03")],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertTrue(bills[0].isPaid)
    }

    func testDueDayUsesMostCommonHistoricalDay() {
        let bills = BillsEngine.bills(
            budgets: [budget(category: "Housing & Utilities", limit: 100, isFixed: true)],
            transactions: [
                txn(category: "Housing & Utilities", amount: 50, date: "2026-01-05"),
                txn(category: "Housing & Utilities", amount: 50, date: "2026-02-05"),
                txn(category: "Housing & Utilities", amount: 50, date: "2026-02-20")
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(bills[0].dueDay, 5)
    }
}
