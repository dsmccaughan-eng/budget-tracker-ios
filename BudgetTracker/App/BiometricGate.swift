import LocalAuthentication
import SwiftUI

@MainActor
final class BiometricGateStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var lastError: String?

    func authenticate(reason: String = "Unlock your budget data") async {
        lastError = nil
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        let hasFaceIDUsageText =
            (Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let canUseBiometrics = hasFaceIDUsageText &&
            context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let policy: LAPolicy = canUseBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            lastError = error?.localizedDescription ?? "Device authentication unavailable."
            isUnlocked = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            isUnlocked = success
        } catch {
            lastError = error.localizedDescription
            isUnlocked = false
        }
    }

    func lock() {
        isUnlocked = false
    }
}

struct BiometricGateView<Content: View>: View {
    @ObservedObject var gate: BiometricGateStore
    @Environment(\.scenePhase) private var scenePhase
    let content: () -> Content

    var body: some View {
        Group {
            if gate.isUnlocked {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "faceid")
                        .font(.system(size: 48))
                    Text("Face ID Required")
                        .font(.title2.bold())
                    Text("Your financial data stays protected until you authenticate.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let lastError = gate.lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button("Unlock") {
                        Task { await gate.authenticate() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                gate.lock()
            }
        }
    }
}
