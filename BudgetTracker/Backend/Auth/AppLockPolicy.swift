import Foundation
import LocalAuthentication

enum AppLockPolicy {
    static let maxBiometricFailures = 3
    static let maxPINFailures = 10
    static let pinLength = 6
    /// Re-lock only after the app has stayed in background at least this long.
    static let backgroundLockGracePeriod: TimeInterval = 30
}

enum AppLockUnlockMode: Equatable {
    case biometric
    case pinAfterBiometricFailures
    case pinOnly
}

struct AppLockChallenge: Equatable {
    let mode: AppLockUnlockMode
    let biometricFailures: Int
}

enum AppLockPolicyEngine {
    static func challenge(
        biometricsAvailable: Bool,
        biometricFailures: Int,
        biometricsEnabled: Bool
    ) -> AppLockChallenge {
        if !biometricsEnabled || !biometricsAvailable ||
            biometricFailures >= AppLockPolicy.maxBiometricFailures {
            return AppLockChallenge(
                mode: .pinOnly,
                biometricFailures: biometricFailures
            )
        }
        if biometricFailures > 0 {
            return AppLockChallenge(
                mode: .pinAfterBiometricFailures,
                biometricFailures: biometricFailures
            )
        }
        return AppLockChallenge(mode: .biometric, biometricFailures: 0)
    }

    static func shouldCountBiometricFailure(_ error: LAError) -> Bool {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return false
        default:
            return true
        }
    }

    static func shouldLockAfterBackgroundDuration(_ elapsed: TimeInterval) -> Bool {
        elapsed >= AppLockPolicy.backgroundLockGracePeriod
    }
}
