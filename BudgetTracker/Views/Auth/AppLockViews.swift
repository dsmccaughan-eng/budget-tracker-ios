import SwiftUI

struct AppLockGateView<Content: View>: View {
    @ObservedObject var lock: AppLockStore
    @Environment(\.scenePhase) private var scenePhase
    let content: () -> Content

    var body: some View {
        ZStack {
            if lock.isUnlocked {
                content()
            }
            if !lock.isUnlocked {
                AppLockUnlockView(lock: lock)
            }
            if scenePhase != .active {
                AppLockPrivacyShieldView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                lock.lock()
            }
        }
    }
}

private struct AppLockPrivacyShieldView: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .accessibilityLabel("App locked")
    }
}

struct AppLockUnlockView: View {
    @ObservedObject var lock: AppLockStore
    @State private var pin = ""
    @State private var didAutoPrompt = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: lockIconName)
                .font(.system(size: 48))
                .accessibilityHidden(true)

            Text(titleText)
                .font(.title2.bold())

            Text(subtitleText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let lastError = lock.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if lock.requiresPINEntry {
                PINEntryField(pin: $pin, length: AppLockPolicy.pinLength)
                    .padding(.top, 8)

                Button("Unlock") {
                    submitPIN()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count < AppLockPolicy.pinLength)

                if lock.biometricsAvailable,
                   lock.biometricsEnabled,
                   lock.currentChallenge.mode != .pinOnly {
                    Button("Use Face ID") {
                        pin = ""
                        Task { await lock.authenticateWithBiometrics() }
                    }
                    .font(.footnote)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Button("Try Face ID Again") {
                        Task { await lock.authenticateWithBiometrics() }
                    }
                    .buttonStyle(.bordered)
                    Button("Use PIN") {
                        lock.forcePINEntry()
                    }
                    .font(.footnote)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .onChange(of: lock.isUnlocked) { _, unlocked in
            if !unlocked { didAutoPrompt = false }
        }
        .onChange(of: pin) { _, newValue in
            if newValue.count == AppLockPolicy.pinLength {
                submitPIN()
            }
        }
        .task(id: lockUnlockTaskID) {
            await promptUnlockIfNeeded()
        }
    }

    private var lockUnlockTaskID: String {
        "\(lock.isUnlocked)-\(lock.requiresPINEntry)-\(lock.biometricFailureCount)"
    }

    private var lockIconName: String {
        lock.requiresPINEntry ? "lock.fill" : "faceid"
    }

    private var titleText: String {
        lock.requiresPINEntry ? "Enter PIN" : "Unlock Budget Tracker"
    }

    private var subtitleText: String {
        if lock.requiresPINEntry {
            return "Your financial data stays protected until you authenticate."
        }
        return "Confirm with Face ID or Touch ID."
    }

    private func submitPIN() {
        guard pin.count == AppLockPolicy.pinLength else { return }
        if lock.verifyPIN(pin) {
            pin = ""
        } else {
            pin = ""
        }
    }

    private func promptUnlockIfNeeded() async {
        guard !lock.isUnlocked, lock.currentChallenge.mode == .biometric else { return }
        guard !didAutoPrompt else { return }
        didAutoPrompt = true
        await lock.authenticateWithBiometrics()
    }
}

struct SetPINView: View {
    @ObservedObject var lock: AppLockStore
    let onComplete: () -> Void

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var step: SetupStep = .enter
    @State private var errorMessage: String?

    private enum SetupStep {
        case enter, confirm
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Secure your budget")
                .font(.title2.bold())

            Text("Create a \(AppLockPolicy.pinLength)-digit PIN. Face ID runs when you open the app; use the PIN if biometrics fail.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            if step == .enter {
                PINEntryField(pin: $pin, length: AppLockPolicy.pinLength, prompt: "New PIN")
                Button("Continue") {
                    guard pin.count == AppLockPolicy.pinLength else { return }
                    errorMessage = nil
                    step = .confirm
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count != AppLockPolicy.pinLength)
            } else {
                PINEntryField(pin: $confirmPIN, length: AppLockPolicy.pinLength, prompt: "Confirm PIN")
                Button("Save PIN") {
                    savePIN()
                }
                .buttonStyle(.borderedProminent)
                .disabled(confirmPIN.count != AppLockPolicy.pinLength)

                Button("Back") {
                    confirmPIN = ""
                    step = .enter
                }
                .font(.footnote)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func savePIN() {
        guard pin == confirmPIN else {
            errorMessage = "PINs do not match. Try again."
            confirmPIN = ""
            return
        }
        do {
            try lock.setPIN(pin)
            lock.unlock()
            lock.refreshConfiguration()
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
            pin = ""
            confirmPIN = ""
            step = .enter
        }
    }
}

struct ChangePINView: View {
    @ObservedObject var lock: AppLockStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var step: Step = .current
    @State private var errorMessage: String?
    @State private var didChangeSucceed = false

    private enum Step {
        case current, newPIN, confirm
    }

    var body: some View {
        Form {
            Section {
                Text(stepLabel)
                PINEntryField(
                    pin: bindingForStep,
                    length: AppLockPolicy.pinLength
                )
                .listRowInsets(EdgeInsets())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Change PIN")
        .navigationBarTitleDisplayMode(.inline)
        .alert("PIN updated", isPresented: $didChangeSucceed) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your app PIN was changed successfully.")
        }
        .onChange(of: currentPIN) { _, value in advanceIfNeeded(value, from: .current) }
        .onChange(of: newPIN) { _, value in advanceIfNeeded(value, from: .newPIN) }
        .onChange(of: confirmPIN) { _, value in
            guard value.count == AppLockPolicy.pinLength, step == .confirm else { return }
            finishChange()
        }
    }

    private var stepLabel: String {
        switch step {
        case .current: return "Current PIN"
        case .newPIN: return "New PIN"
        case .confirm: return "Confirm new PIN"
        }
    }

    private var bindingForStep: Binding<String> {
        switch step {
        case .current: return $currentPIN
        case .newPIN: return $newPIN
        case .confirm: return $confirmPIN
        }
    }

    private func advanceIfNeeded(_ value: String, from expected: Step) {
        guard value.count == AppLockPolicy.pinLength, step == expected else { return }
        switch expected {
        case .current:
            guard lock.checkPIN(value) else {
                errorMessage = "Incorrect PIN."
                currentPIN = ""
                return
            }
            errorMessage = nil
            step = .newPIN
        case .newPIN:
            if value == currentPIN {
                errorMessage = "New PIN must be different from your current PIN."
                newPIN = ""
                return
            }
            errorMessage = nil
            step = .confirm
        case .confirm:
            break
        }
    }

    private func finishChange() {
        guard newPIN == confirmPIN else {
            errorMessage = "PINs do not match."
            confirmPIN = ""
            step = .newPIN
            return
        }
        do {
            try lock.changePIN(currentPIN: currentPIN, newPIN: newPIN)
            didChangeSucceed = true
        } catch {
            errorMessage = error.localizedDescription
            newPIN = ""
            confirmPIN = ""
            step = .newPIN
        }
    }
}
