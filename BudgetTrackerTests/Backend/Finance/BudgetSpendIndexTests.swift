import XCTest
@testable import BudgetTracker

final class BudgetSpendIndexTests: XCTestCase {
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
            merchantName: "Store",
            name: "Store",
            category: category,
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
    }

    func testIndexSpentMatchesLegacyMath() {
        let txns = [
            txn(category: "Groceries", amount: 40, date: "2026-05-10"),
            txn(category: "Groceries", amount: 20, date: "2026-04-30"),
            txn(category: "Dining & Bars", amount: 15, date: "2026-05-11")
        ]
        let index = BudgetSpendIndex(transactions: txns, calendar: calendar)
        let spent = index.spent(category: "Groceries", referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(spent, 40, accuracy: 0.01)
    }

    func testIndexIgnoresExcludedTransactions() {
        let txns = [
            txn(category: "Groceries", amount: 40, date: "2026-05-10"),
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: UUID().uuidString,
                amount: 100,
                date: "2026-05-11",
                merchantName: "Store",
                name: "Store",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                excludedFromBudget: true
            )
        ]
        let index = BudgetSpendIndex(transactions: txns, calendar: calendar)
        let spent = index.spent(category: "Groceries", referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(spent, 40, accuracy: 0.01)
    }

    func testSuggestedPlanLinesSumToTotal() {
        let txns = [
            txn(category: "Groceries", amount: 300, date: "2026-05-01"),
            txn(category: "Dining & Bars", amount: 100, date: "2026-05-02")
        ]
        let lines = BudgetMath.suggestedPlanLines(
            total: 2000,
            transactions: txns,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let sum = lines.reduce(0) { $0 + $1.monthlyLimit }
        XCTAssertEqual(sum, 2000, accuracy: 0.02)
        XCTAssertEqual(lines.count, BudgetMath.budgetableCategories.count)
        XCTAssertFalse(lines.contains { $0.color.isEmpty })
    }

    func testMonthRowsUsesIndexRecentSummary() {
        let budgets = [
            Budget(
                id: UUID(),
                category: "Groceries",
                monthlyLimit: 500,
                color: "#22c55e",
                isRollover: false,
                isFixed: false
            )
        ]
        let txns = [
            txn(category: "Groceries", amount: 10, date: "2026-05-20"),
            txn(category: "Groceries", amount: 12, date: "2026-05-18")
        ]
        let index = BudgetSpendIndex(transactions: txns, calendar: calendar)
        let rows = BudgetMath.monthRows(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].recentSummary.contains("Store"))
    }
}
