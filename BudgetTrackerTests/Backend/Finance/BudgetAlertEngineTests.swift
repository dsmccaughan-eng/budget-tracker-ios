import XCTest
@testable import BudgetTracker

final class BudgetAlertEngineTests: XCTestCase {
    func testAlertWhenOverThreshold() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 85,
            projectedSpend: 120,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertEqual(alerts.count, 1)
    }

    func testSkipsFixedBudgetAtThreshold() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBillCategoryAtThreshold() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(
            progress: [row],
            threshold: 0.8,
            fixedBillCategories: ["Housing & Utilities"]
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
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 2_100,
            projectedSpend: 2_100,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }
}
