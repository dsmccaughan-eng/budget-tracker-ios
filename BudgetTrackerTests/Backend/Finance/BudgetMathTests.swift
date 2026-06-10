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

    func testRecentMerchantSummaryJoinsNames() {
        let txns = [
            txn(category: "Groceries", amount: 10, date: "2026-05-20"),
            txn(category: "Groceries", amount: 12, date: "2026-05-18"),
            txn(category: "Dining & Bars", amount: 8, date: "2026-05-19")
        ]
        let summary = BudgetMath.recentMerchantSummary(
            transactions: txns,
            category: "Groceries",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertTrue(summary.contains("Test"))
    }

    func testProjectedSpendScalesToMonthEnd() {
        let projected = BudgetMath.projectedMonthlySpend(
            spent: 150,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(projected, 310, accuracy: 0.01)
    }

    func testAverageMonthlySpendUsesLastSixMonths() {
        let txns = [
            txn(category: "Groceries", amount: 60, date: "2026-05-10"),
            txn(category: "Groceries", amount: 40, date: "2026-04-10"),
            txn(category: "Groceries", amount: 100, date: "2026-03-10"),
            txn(category: "Groceries", amount: 20, date: "2026-02-10")
        ]
        let average = BudgetMath.averageMonthlySpend(
            transactions: txns,
            category: "Groceries",
            referenceDate: referenceDate,
            monthCount: 6,
            calendar: calendar
        )
        XCTAssertEqual(average, 220.0 / 6.0, accuracy: 0.01)
    }

    func testDisplayMonthRowsIncludesUnbudgetedCategoriesWithActivity() {
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
            txn(category: "Groceries", amount: 40, date: "2026-05-10"),
            txn(category: "Other", amount: 25, date: "2026-05-11"),
            txn(category: "Income", amount: -2000, date: "2026-05-01"),
            txn(category: "Transfers", amount: 500, date: "2026-05-02")
        ]
        let index = BudgetSpendIndex(transactions: txns, calendar: calendar)
        let chartRows = BudgetMath.monthRows(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let sections = BudgetMath.displayMonthSections(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(chartRows.map(\.progress.category), ["Groceries"])
        XCTAssertEqual(sections.spending.count, 2)
        XCTAssertEqual(sections.income.count, 1)
        XCTAssertEqual(sections.transfers.count, 1)
        let income = sections.income.first
        XCTAssertEqual(income?.progress.listDisplaySpent ?? 0, 2000, accuracy: 0.01)
        let spendingTotal = BudgetMath.monthSpendingDisplayTotal(rows: sections.spending)
        XCTAssertEqual(spendingTotal, 65, accuracy: 0.01)
    }

    func testMonthSpendingDisplayTotalDropsExcludedTransactions() {
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
            txn(category: "Groceries", amount: 40, date: "2026-05-10"),
            Transaction(
                id: UUID(),
                accountId: UUID(),
                plaidTransactionId: UUID().uuidString,
                amount: 100,
                date: "2026-05-11",
                merchantName: "Test",
                name: "Test",
                category: "Groceries",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil,
                excludedFromBudget: true
            )
        ]
        let index = BudgetSpendIndex(transactions: txns, calendar: calendar)
        let sections = BudgetMath.displayMonthSections(
            budgets: budgets,
            index: index,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(BudgetMath.monthSpendingDisplayTotal(rows: sections.spending), 40, accuracy: 0.01)
    }

    func testProgressRowsSortsBySpentDescending() {
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
                category: "Dining & Bars",
                monthlyLimit: 300,
                color: "#ea580c",
                isRollover: false,
                isFixed: false
            )
        ]
        let txns = [
            txn(category: "Groceries", amount: 50, date: "2026-05-01"),
            txn(category: "Dining & Bars", amount: 200, date: "2026-05-02")
        ]
        let rows = BudgetMath.progressRows(
            budgets: budgets,
            transactions: txns,
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(rows.first?.category, "Dining & Bars")
    }

    func testProgressRowsUsesSixMonthAverageForProjection() {
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
            txn(category: "Groceries", amount: 100, date: "2026-05-01"),
            txn(category: "Groceries", amount: 200, date: "2026-04-01"),
            txn(category: "Groceries", amount: 300, date: "2026-03-01")
        ]
        let rows = BudgetMath.progressRows(
            budgets: budgets,
            transactions: txns,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let groceries = rows.first { $0.category == "Groceries" }
        XCTAssertEqual(groceries?.spent ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(groceries?.projectedSpend ?? 0, 100, accuracy: 0.01)
    }
}
