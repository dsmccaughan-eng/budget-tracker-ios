import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var otp = ""
    @State private var step: Step = .email
    @State private var isLoading = false

    enum Step { case email, otp }

    var body: some View {
        NavigationStack {
            Form {
                if step == .email {
                    emailSection
                } else {
                    otpSection
                }

                if let errorMessage = auth.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Budget Tracker")
        }
    }

    private var emailSection: some View {
        Section {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)

            Button {
                sendCode()
            } label: {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Send sign-in code")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        } header: {
            Text("Sign in")
        } footer: {
            Text("We'll email a one-time code. If email is slow, your code may appear on the next screen.")
        }
    }

    private var otpSection: some View {
        Section {
            if let inApp = auth.pendingInAppOTP {
                Text("Your sign-in code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(inApp)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                Text("Email delivery is unavailable — use the code above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter the code sent to \(email)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("6-digit code", text: $otp)
                .keyboardType(.numberPad)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)

            Button {
                verifyCode()
            } label: {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(otp.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 || isLoading)

            Button("Use a different email") {
                step = .email
                otp = ""
                auth.pendingInAppOTP = nil
                auth.errorMessage = nil
            }
        } header: {
            Text("Check your email")
        }
    }

    private func sendCode() {
        guard !isLoading else { return }
        isLoading = true
        auth.errorMessage = nil
        Task {
            await auth.sendOTP(email: email)
            await MainActor.run {
                if auth.errorMessage == nil || auth.pendingInAppOTP != nil {
                    if let code = auth.pendingInAppOTP {
                        otp = code
                    }
                    step = .otp
                }
                isLoading = false
            }
        }
    }

    private func verifyCode() {
        guard !isLoading else { return }
        isLoading = true
        auth.errorMessage = nil
        Task {
            await auth.verifyOTP(email: email, token: otp)
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
