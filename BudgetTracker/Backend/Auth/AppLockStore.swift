import Foundation
import LocalAuthentication

@MainActor
final class AppLockStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var hasPIN = false
    @Published private(set) var lastError: String?
    @Published private(set) var biometricFailureCount = 0
    @Published private(set) var pinFailureCount = 0
    @Published var biometricsEnabled = true {
        didSet {
            UserDefaults.standard.set(biometricsEnabled, forKey: Self.biometricsEnabledKey)
        }
    }

    private static let biometricsEnabledKey = "appLock.biometricsEnabled"

    private var cachedVerifier: PINKeychainStore.Verifier?
    private var backgroundLockTask: Task<Void, Never>?

    init() {
        if UserDefaults.standard.object(forKey: Self.biometricsEnabledKey) != nil {
            biometricsEnabled = UserDefaults.standard.bool(forKey: Self.biometricsEnabledKey)
        }
    }

    var currentChallenge: AppLockChallenge {
        AppLockPolicyEngine.challenge(
            biometricsAvailable: biometricsAvailable,
            biometricFailures: biometricFailureCount,
            biometricsEnabled: biometricsEnabled
        )
    }

    var requiresPINEntry: Bool {
        currentChallenge.mode == .pinOnly
    }

    var isPINLockedOut: Bool {
        pinFailureCount >= AppLockPolicy.maxPINFailures
    }

    /// No PIN configured yet, or user passed the lock screen.
    var canAccessFinancialData: Bool {
        !hasPIN || isUnlocked
    }

    private(set) var biometricsAvailable = false

    func refreshConfiguration() {
        cachedVerifier = try? PINKeychainStore.load()
        hasPIN = cachedVerifier != nil
        let context = LAContext()
        var error: NSError?
        let hasUsageDescription = (Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        biometricsAvailable = hasUsageDescription &&
            context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func setPIN(_ pin: String) throws {
        guard PINHasher.isValidPINFormat(pin) else {
            throw AppLockStoreError.invalidPINFormat
        }
        let salt = try PINHasher.generateSalt()
        let hash = try PINHasher.hash(pin: pin, salt: salt)
        guard hash.count == PINHasher.derivedKeyLength else {
            throw AppLockStoreError.pinStorageFailed
        }
        let verifier = PINKeychainStore.Verifier(salt: salt, hash: hash)
        try PINKeychainStore.save(verifier: verifier)
        cachedVerifier = verifier
        hasPIN = true
        lastError = nil
        pinFailureCount = 0
    }

    func changePIN(currentPIN: String, newPIN: String) throws {
        guard checkPIN(currentPIN) else {
            throw AppLockStoreError.incorrectPIN
        }
        guard currentPIN != newPIN else {
            throw AppLockStoreError.samePIN
        }
        try setPIN(newPIN)
    }

    func checkPIN(_ pin: String) -> Bool {
        guard let verifier = cachedVerifier ?? (try? PINKeychainStore.load()) else {
            return false
        }
        cachedVerifier = verifier
        return PINHasher.verify(pin: pin, salt: verifier.salt, expectedHash: verifier.hash)
    }

    @discardableResult
    func verifyPIN(_ pin: String) -> Bool {
        if isPINLockedOut {
            lastError = "Too many PIN attempts. Try again later or restart the app."
            return false
        }
        guard checkPIN(pin) else {
            pinFailureCount += 1
            lastError = "Incorrect PIN."
            return false
        }
        unlock()
        return true
    }

    func authenticateWithBiometrics(reason: String = "Unlock your budget data") async {
        lastError = nil
        guard biometricsEnabled, biometricsAvailable else {
            lastError = "Biometrics unavailable. Use your PIN."
            return
        }
        guard !requiresPINEntry else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        context.localizedFallbackTitle = "Enter PIN"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError, laError.code == .biometryNotAvailable {
                lastError = "Face ID is not ready yet. Wait a moment, then tap Try Face ID Again."
            } else {
                lastError = error?.localizedDescription ?? "Biometrics unavailable."
            }
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success {
                unlock()
            } else {
                recordBiometricFailure()
            }
        } catch let laError as LAError {
            handleBiometricError(laError)
        } catch {
            lastError = error.localizedDescription
            recordBiometricFailure()
        }
    }

    func lock() {
        isUnlocked = false
    }

    func handleEnterBackground() {
        backgroundLockTask?.cancel()
        backgroundLockTask = Task { [weak self] in
            let delay = AppLockPolicy.backgroundLockGracePeriod
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.lock()
        }
    }

    func handleEnterForeground() {
        backgroundLockTask?.cancel()
        backgroundLockTask = nil
    }

    func unlock() {
        isUnlocked = true
        lastError = nil
        biometricFailureCount = 0
        pinFailureCount = 0
    }

    func recordBiometricFailure() {
        biometricFailureCount += 1
        if biometricFailureCount >= AppLockPolicy.maxBiometricFailures {
            lastError = "Too many attempts. Enter your PIN."
        }
    }

    func resetBiometricFailures() {
        biometricFailureCount = 0
        lastError = nil
    }

    func forcePINEntry() {
        biometricFailureCount = AppLockPolicy.maxBiometricFailures
        lastError = nil
    }

    private func handleBiometricError(_ error: LAError) {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            break
        case .userFallback:
            biometricFailureCount = AppLockPolicy.maxBiometricFailures
            lastError = "Enter your PIN."
        case .biometryLockout:
            biometricFailureCount = AppLockPolicy.maxBiometricFailures
            lastError = "Biometrics locked. Enter your PIN."
        case .biometryNotAvailable:
            lastError = "Face ID is not ready yet. Wait a moment, then tap Try Face ID Again."
        default:
            lastError = error.localizedDescription
            if AppLockPolicyEngine.shouldCountBiometricFailure(error) {
                recordBiometricFailure()
            }
        }
    }
}

enum AppLockStoreError: Error, LocalizedError {
    case invalidPINFormat
    case incorrectPIN
    case samePIN
    case pinStorageFailed

    var errorDescription: String? {
        switch self {
        case .invalidPINFormat:
            return "PIN must be exactly 6 digits."
        case .incorrectPIN:
            return "Current PIN is incorrect."
        case .samePIN:
            return "New PIN must be different from your current PIN."
        case .pinStorageFailed:
            return "Could not save PIN securely. Try again."
        }
    }
}
