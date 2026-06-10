import XCTest
@testable import BudgetTracker

final class AppLockPolicyTests: XCTestCase {
    func testBiometricFirstWhenAvailable() {
        let challenge = AppLockPolicyEngine.challenge(
            biometricsAvailable: true,
            biometricFailures: 0,
            biometricsEnabled: true
        )
        XCTAssertEqual(challenge.mode, .biometric)
    }

    func testPINAfterMaxFailures() {
        let challenge = AppLockPolicyEngine.challenge(
            biometricsAvailable: true,
            biometricFailures: AppLockPolicy.maxBiometricFailures,
            biometricsEnabled: true
        )
        XCTAssertEqual(challenge.mode, .pinOnly)
    }

    func testPINOnlyWhenBiometricsDisabled() {
        let challenge = AppLockPolicyEngine.challenge(
            biometricsAvailable: true,
            biometricFailures: 0,
            biometricsEnabled: false
        )
        XCTAssertEqual(challenge.mode, .pinOnly)
    }

    func testSingleBiometricFailureStillAllowsBiometricFirst() {
        let challenge = AppLockPolicyEngine.challenge(
            biometricsAvailable: true,
            biometricFailures: 1,
            biometricsEnabled: true
        )
        XCTAssertEqual(challenge.mode, .pinAfterBiometricFailures)
    }

    func testBackgroundGracePeriodIsThirtySeconds() {
        XCTAssertEqual(AppLockPolicy.backgroundLockGracePeriod, 30)
    }

    func testShouldLockAfterGracePeriod() {
        XCTAssertFalse(AppLockPolicyEngine.shouldLockAfterBackgroundDuration(29))
        XCTAssertTrue(AppLockPolicyEngine.shouldLockAfterBackgroundDuration(30))
        XCTAssertTrue(AppLockPolicyEngine.shouldLockAfterBackgroundDuration(120))
    }
}
