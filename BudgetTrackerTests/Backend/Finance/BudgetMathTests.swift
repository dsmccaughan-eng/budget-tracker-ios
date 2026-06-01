import XCTest
@testable import BudgetTracker

final class BudgetMathTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
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

    func testSpentAmountFiltersByCategoryAndMonth() {
        let txns = [
            txn(category: "Groceries", amount: 40, date: "2026-05-10"),
            txn(category: "Groceries", amount: 20, date: "2026-04-30"),
            txn(category: "Dining & Bars", amount: 15, date: "2026-05-11")
        ]
        let spent = BudgetMath.spentAmount(
            transactions: txns,
            category: "Groceries",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(spent, 40, accuracy: 0.01)
    }

    func testProjectedSpendScalesToMonthEnd() {
        let projected = BudgetMath.projectedMonthlySpend(
            spent: 150,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(projected, 300, accuracy: 0.01)
    }

    func testProgressRowsMarksFixedBudgetProjectedAsSpent() {
        let budgets = [
            Budget(
                id: UUID(),
                category: "Groceries",
                monthlyLimit: 500,
                color: "#22c55e",
                isRollover: false,
                isFixed: false
            ),
            Budget(
                id: UUID(),
                category: "Housing & Utilities",
                monthlyLimit: 1500,
                color: "#3b82f6",
                isRollover: false,
                isFixed: true
            )
        ]
        let txns = [
            txn(category: "Groceries", amount: 100, date: "2026-05-01"),
            txn(category: "Housing & Utilities", amount: 1500, date: "2026-05-01")
        ]
        let rows = BudgetMath.progressRows(
            budgets: budgets,
            transactions: txns,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let groceries = rows.first { $0.category == "Groceries" }
        let housing = rows.first { $0.category == "Housing & Utilities" }
        XCTAssertEqual(groceries?.spent, 100, accuracy: 0.01)
        XCTAssertGreaterThan(groceries?.projectedSpend ?? 0, 100)
        XCTAssertEqual(housing?.projectedSpend, housing?.spent)
    }
}
