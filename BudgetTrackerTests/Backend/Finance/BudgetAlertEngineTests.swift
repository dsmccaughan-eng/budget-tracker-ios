import XCTest
@testable import BudgetTracker

final class BudgetAlertEngineTests: XCTestCase {
    func testAlertWhenSpentExceedsTypicalByNow() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 500,
            spent: 120,
            projectedSpend: 200,
            typicalByNow: 100,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row])
        XCTAssertTrue(alerts.contains { $0.contains("Groceries") && $0.contains("typical") })
    }

    func testNoAlertWhenUnderTypicalEvenIfMostOfBudgetUsed() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 85,
            projectedSpend: 90,
            typicalByNow: 90,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        XCTAssertTrue(BudgetAlertEngine.alerts(progress: [row]).isEmpty)
    }

    func testAlertWhenOverBudgetEvenIfUnderTypical() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 110,
            projectedSpend: 150,
            typicalByNow: 200,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row])
        XCTAssertTrue(alerts.contains { $0.contains("over budget") })
    }

    func testOverallAlertWhenTotalExceedsTypical() {
        let rows = [
            BudgetProgress(
                category: "Groceries",
                monthlyLimit: 200,
                spent: 90,
                projectedSpend: 80,
                typicalByNow: 80,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
            BudgetProgress(
                category: "Dining & Bars",
                monthlyLimit: 200,
                spent: 90,
                projectedSpend: 80,
                typicalByNow: 80,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
        ]
        let alerts = BudgetAlertEngine.alerts(progress: rows)
        XCTAssertTrue(alerts.contains { $0.contains("Overall") && $0.contains("typical") })
    }

    func testAlertWhenOverThreshold() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 85,
            projectedSpend: 120,
            typicalByNow: 80,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.contains { $0.contains("Groceries") })
    }

    func testAlertsForAllAllowlistedCategories() {
        let categories = [
            "Groceries",
            "Dining & Bars",
            "Shopping",
            "Entertainment",
            "Transport",
        ]
        let rows = categories.map { category in
            BudgetProgress(
                category: category,
                monthlyLimit: 100,
                spent: 85,
                projectedSpend: 100,
                typicalByNow: 80,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            )
        }
        let alerts = BudgetAlertEngine.alerts(progress: rows, threshold: 0.8)
        XCTAssertEqual(alerts.filter { $0.contains("typical") && !$0.contains("Overall") }.count, 5)
    }

    func testSkipsNonAllowlistedCategoriesEvenWhenOverBudget() {
        let rows = [
            BudgetProgress(
                category: "Health & Wellness",
                monthlyLimit: 100,
                spent: 150,
                projectedSpend: 150,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
            BudgetProgress(
                category: "Travel",
                monthlyLimit: 200,
                spent: 190,
                projectedSpend: 200,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
            BudgetProgress(
                category: "Other",
                monthlyLimit: 50,
                spent: 80,
                projectedSpend: 80,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
        ]
        let alerts = BudgetAlertEngine.alerts(progress: rows, threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBudgetAtThreshold() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 90,
            projectedSpend: 100,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBillCategoryAtThreshold() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 90,
            projectedSpend: 100,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(
            progress: [row],
            threshold: 0.8,
            fixedBillCategories: ["Groceries"]
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBillTransactionCategoryViaTransactionsParameter() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let rent = Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: 1_800,
            date: "2026-06-01",
            merchantName: "Landlord",
            name: "Landlord",
            category: "Housing & Utilities",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil,
            isFixedBill: true
        )
        let alerts = BudgetAlertEngine.alerts(
            progress: [row],
            transactions: [rent],
            threshold: 0.8
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsHousingEvenWhenVariable() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsSubscriptionsAndInsuranceEvenWhenVariable() {
        let rows = [
            BudgetProgress(
                category: "Subscriptions",
                monthlyLimit: 120,
                spent: 115,
                projectedSpend: 120,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
            BudgetProgress(
                category: "Insurance",
                monthlyLimit: 300,
                spent: 290,
                projectedSpend: 300,
                isFixed: false,
                isRollover: false,
                color: "#000000"
            ),
        ]
        let alerts = BudgetAlertEngine.alerts(progress: rows, threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBudgetWhenOverBudget() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 120,
            projectedSpend: 120,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }
}
