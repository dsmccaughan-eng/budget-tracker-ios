import XCTest
@testable import BudgetTracker

final class ConnectionPolicyEngineTests: XCTestCase {
    func testSandboxAlwaysPlaid() {
        XCTAssertEqual(
            ConnectionPolicyEngine.preferredProvider(
                plaidEnvironment: "sandbox",
                globalPlaidItemCount: 99,
                tellerConfigured: true
            ),
            .plaid
        )
    }

    func testUnderTrialCapUsesPlaid() {
        XCTAssertEqual(
            ConnectionPolicyEngine.preferredProvider(
                plaidEnvironment: "production",
                globalPlaidItemCount: 9,
                plaidTrialLimit: 10,
                tellerConfigured: true
            ),
            .plaid
        )
    }

    func testAtTrialCapUsesTeller() {
        XCTAssertEqual(
            ConnectionPolicyEngine.preferredProvider(
                plaidEnvironment: "production",
                globalPlaidItemCount: 10,
                plaidTrialLimit: 10,
                tellerConfigured: true
            ),
            .teller
        )
    }

    func testWithoutTellerStaysPlaid() {
        XCTAssertEqual(
            ConnectionPolicyEngine.preferredProvider(
                plaidEnvironment: "production",
                globalPlaidItemCount: 50,
                tellerConfigured: false
            ),
            .plaid
        )
    }
}
