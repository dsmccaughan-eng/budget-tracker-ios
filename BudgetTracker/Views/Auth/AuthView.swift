import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var otp = ""
    @State private var step: Step = .email
    @State private var isLoading = false

    @State private var supabaseAnonKey = ""
    @State private var showBackendSetup = false

    enum Step { case email, otp }

    var body: some View {
        NavigationStack {
            Form {
                if showBackendSetup {
                    backendSection
                }

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
            .onAppear {
                showBackendSetup = false
            }
        }
    }

    private var backendSection: some View {
        Section {
            Text("Supabase anon key")
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField("Anon public key", text: $supabaseAnonKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("Project URL: \(APIKeys.defaultSupabaseURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Save backend key") {
                APIKeys.saveUserSupabaseKeys(url: APIKeys.defaultSupabaseURL, anonKey: supabaseAnonKey)
                showBackendSetup = false
                auth.errorMessage = nil
                Task { await auth.bootstrap() }
            }
            .disabled(supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
        } header: {
            Text("Backend")
        } footer: {
            Text("Required once per device. Find the anon key in Supabase Dashboard → Project Settings → API.")
        }
    }

    private var emailSection: some View {
        Section {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()

            Button {
                sendCode()
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Send sign-in code")
                }
            }
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || !SupabaseConfig.isConfigured)
        } header: {
            Text("Sign in")
        } footer: {
            Text("We'll email a one-time code. No password to remember.")
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
                if isLoading {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .disabled(otp.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 || isLoading)

            Button("Use a different email") {
                step = .email
                otp = ""
                auth.pendingInAppOTP = nil
            }
        } header: {
            Text("Check your email")
        }
    }

    private func sendCode() {
        isLoading = true
        Task {
            await auth.sendOTP(email: email)
            if auth.errorMessage == nil || auth.pendingInAppOTP != nil {
                if let code = auth.pendingInAppOTP {
                    otp = code
                }
                step = .otp
            }
            isLoading = false
        }
    }

    private func verifyCode() {
        isLoading = true
        Task {
            await auth.verifyOTP(email: email, token: otp)
            isLoading = false
        }
    }
}
