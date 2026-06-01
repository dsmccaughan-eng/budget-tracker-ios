import XCTest
@testable import BudgetTracker

final class TransactionFormattingTests: XCTestCase {
    func testRefundDisplaysAsPositiveCredit() {
        XCTAssertTrue(TransactionFormatting.isInflow(-25))
        XCTAssertEqual(TransactionFormatting.formattedAmount(-25), "+$25.00")
        XCTAssertEqual(TransactionFormatting.amountLabel(-25), "Credit")
    }

    func testExpenseDisplaysAsNegativeOutflow() {
        XCTAssertTrue(TransactionFormatting.isOutflow(40))
        XCTAssertEqual(TransactionFormatting.formattedAmount(40), "-$40.00")
        XCTAssertEqual(TransactionFormatting.amountLabel(40), "Expense")
    }
}

final class BudgetMathRefundTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testSpentAmountSubtractsRefunds() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        let txns = [
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: "1",
                amount: 100,
                date: "2026-05-10",
                merchantName: "Store",
                name: "Store",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                categorySource: nil
            ),
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: "2",
                amount: -20,
                date: "2026-05-12",
                merchantName: "Store",
                name: "Refund",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                categorySource: nil
            )
        ]
        let spent = BudgetMath.spentAmount(
            transactions: txns,
            category: "Groceries",
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertEqual(spent, 80, accuracy: 0.01)
    }

    func testTransactionsForCategoryFiltersMonth() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let txns = [
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: "1",
                amount: 10,
                date: "2026-05-02",
                merchantName: "A",
                name: "A",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                categorySource: nil
            ),
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: "2",
                amount: 12,
                date: "2026-04-28",
                merchantName: "B",
                name: "B",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                categorySource: nil
            )
        ]
        let rows = BudgetMath.transactionsForCategory(
            transactions: txns,
            category: "Groceries",
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "A")
    }
}
