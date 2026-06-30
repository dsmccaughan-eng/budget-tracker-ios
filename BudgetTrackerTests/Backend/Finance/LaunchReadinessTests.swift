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

    func testAccountDecodesMissingProviderAndStringBalance() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "plaid_item_id": "item_1",
          "plaid_account_id": "acct_1",
          "name": "Checking",
          "type": "depository",
          "current_balance": "1234.56"
        }
        """.data(using: .utf8)!
        let account = try JSONDecoder().decode(Account.self, from: json)
        XCTAssertEqual(account.provider, "plaid")
        XCTAssertEqual(account.currentBalance ?? 0, 1234.56, accuracy: 0.01)
    }
}
