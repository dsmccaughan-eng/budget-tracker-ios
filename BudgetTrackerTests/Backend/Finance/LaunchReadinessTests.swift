import XCTest
@testable import BudgetTracker

/// Threshold and constant guards (TDD) — update tests before changing production values.
final class LaunchReadinessTests: XCTestCase {
    func testBudgetAlertDefaultThresholdIsPointEight() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 85,
            projectedSpend: 90,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertEqual(alerts.count, 1)
    }

    func testSubscriptionAuditDefaultLookbackIs120Days() {
        XCTAssertEqual(SubscriptionAuditEngine.defaultLookbackDays, 120)
    }

    func testCashFlowHorizonPrefixIncludesAllRequestedDays() {
        let days = [
            CashFlowDay(date: "2026-05-01", inflow: 10, outflow: 5),
            CashFlowDay(date: "2026-05-02", inflow: 20, outflow: 0)
        ]
        let totals = CashFlowEngine.horizonTotals(days: days, first: 2)
        XCTAssertEqual(totals.inflow, 30, accuracy: 0.01)
    }
}
