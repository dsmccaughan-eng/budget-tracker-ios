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

    func testChartSliceSegmentsSumToFullSemicircle() {
        let progress = [
            BudgetProgress(
                category: "Groceries",
                monthlyLimit: 500,
                spent: 400,
                projectedSpend: 400,
                isFixed: false,
                isRollover: false,
                color: "#22c55e"
            ),
            BudgetProgress(
                category: "Dining & Bars",
                monthlyLimit: 300,
                spent: 100,
                projectedSpend: 100,
                isFixed: false,
                isRollover: false,
                color: "#ea580c"
            ),
            BudgetProgress(
                category: "Shopping",
                monthlyLimit: 200,
                spent: 0,
                projectedSpend: 0,
                isFixed: false,
                isRollover: false,
                color: "#9333ea"
            )
        ]
        let plan = BudgetMath.chartSliceSegments(progress: progress)
        XCTAssertEqual(plan.total, 500, accuracy: 0.01)
        XCTAssertEqual(plan.segments.count, 2)
        XCTAssertEqual(plan.segments.first?.startFraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.segments.last?.endFraction ?? 0, 1, accuracy: 0.0001)
        let spanSum = plan.segments.reduce(0) { $0 + ($1.endFraction - $1.startFraction) }
        XCTAssertEqual(spanSum, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[0].amount, 400, accuracy: 0.01)
        XCTAssertEqual(plan.segments[1].amount, 100, accuracy: 0.01)
        XCTAssertEqual(plan.segments[0].endFraction, 0.8, accuracy: 0.0001)
    }

    func testChartSegmentCyclesWithSlideDirection() {
        let segments = [
            BudgetChartSliceSegment(
                progress: BudgetProgress(
                    category: "Groceries",
                    monthlyLimit: 500,
                    spent: 400,
                    projectedSpend: 400,
                    isFixed: false,
                    isRollover: false,
                    color: "#22c55e"
                ),
                amount: 400,
                startFraction: 0,
                endFraction: 0.8
            ),
            BudgetChartSliceSegment(
                progress: BudgetProgress(
                    category: "Dining & Bars",
                    monthlyLimit: 300,
                    spent: 100,
                    projectedSpend: 100,
                    isFixed: false,
                    isRollover: false,
                    color: "#ea580c"
                ),
                amount: 100,
                startFraction: 0.8,
                endFraction: 1
            )
        ]
        XCTAssertEqual(
            BudgetMath.chartSegment(atStep: 1, from: 0, segments: segments)?.progress.category,
            "Dining & Bars"
        )
        XCTAssertEqual(
            BudgetMath.chartSegment(atStep: -1, from: 0, segments: segments)?.progress.category,
            "Dining & Bars"
        )
        XCTAssertEqual(
            BudgetMath.chartSegment(containingArcFraction: 0.1, segments: segments)?.progress.category,
            "Groceries"
        )
    }
}
