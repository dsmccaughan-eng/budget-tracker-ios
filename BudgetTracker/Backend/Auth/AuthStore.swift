import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case loading
        case unauthenticated
        case authenticated
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var userId: String?
    @Published var errorMessage: String?

    /// Set only when Supabase email delivery failed and allowlisted fallback returned a code.
    @Published var pendingInAppOTP: String?

    private var client: SupabaseClient?

    init(injectedClient: SupabaseClient? = nil) {
        client = injectedClient
    }

    var activeSupabaseClient: SupabaseClient? {
        guard state == .authenticated, let client else { return nil }
        return client
    }

    var supabaseClient: SupabaseClient {
        guard let client = activeSupabaseClient else {
            fatalError("Supabase client accessed before authentication bootstrap completed.")
        }
        return client
    }

    private func makeClient() throws -> SupabaseClient {
        if let client { return client }

        guard let url = SupabaseConfig.url, SupabaseConfig.isConfigured else {
            throw BudgetTrackerError.server(Self.configurationErrorMessage)
        }

        let created = try SupabaseClientFactory.makeClient(url: url, anonKey: SupabaseConfig.anonKey)
        client = created
        return created
    }

    private static let configurationErrorMessage =
        "App configuration error. Install the latest TestFlight build and try again."

    func bootstrap() async {
        errorMessage = nil
        client = nil
        pendingInAppOTP = nil
        APIKeys.syncToUserDefaultsIfNeeded()

        guard SupabaseConfig.isConfigured else {
            userId = nil
            state = .unauthenticated
            errorMessage = Self.configurationErrorMessage
            return
        }

        do {
            let activeClient = try makeClient()
            let session = try await activeClient.auth.session
            userId = session.user.id.uuidString
            state = .authenticated
        } catch {
            client = nil
            userId = nil
            state = .unauthenticated
        }
    }

    /// Requests email OTP via Supabase. In-app code is used only when email send fails (allowlisted fallback).
    func sendOTP(email: String) async {
        errorMessage = nil
        pendingInAppOTP = nil
        client = nil
        APIKeys.syncToUserDefaultsIfNeeded()

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard SupabaseConfig.isConfigured else {
            state = .unauthenticated
            errorMessage = Self.configurationErrorMessage
            return
        }

        do {
            let activeClient = try makeClient()
            try await activeClient.auth.signInWithOTP(
                email: normalized,
                redirectTo: nil,
                shouldCreateUser: true
            )
            errorMessage = nil
        } catch {
            if await tryInAppFallback(after: error, email: normalized) {
                return
            }
            client = nil
            errorMessage = friendlyOTPError(error)
            state = .unauthenticated
        }
    }

    func verifyOTP(email: String, token: String) async {
        errorMessage = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SupabaseConfig.isConfigured else {
            errorMessage = Self.configurationErrorMessage
            return
        }

        guard code.count >= 6 else {
            errorMessage = "Enter the 6-digit code from your email."
            return
        }

        do {
            let activeClient = try makeClient()
            let response = try await activeClient.auth.verifyOTP(
                email: normalizedEmail,
                token: code,
                type: .email
            )
            guard let session = response.session else {
                errorMessage = "Sign-in incomplete. Request a new code and try again."
                client = nil
                state = .unauthenticated
                return
            }
            userId = session.user.id.uuidString
            state = .authenticated
            pendingInAppOTP = nil
        } catch {
            client = nil
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func signOut() async {
        if let client {
            do {
                try await client.auth.signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        client = nil
        userId = nil
        pendingInAppOTP = nil
        state = .unauthenticated
    }

    private func tryInAppFallback(after error: Error, email: String) async -> Bool {
        guard isLikelyEmailDeliveryFailure(error) else { return false }
        return await deliverInAppOTP(email: email)
    }

    private func isLikelyEmailDeliveryFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("email")
            || message.contains("smtp")
            || message.contains("mail")
            || message.contains("hook")
            || message.contains("send")
    }

    private func deliverInAppOTP(email: String) async -> Bool {
        do {
            if let inApp = try await AuthOTPBridge.requestInAppOTP(email: email) {
                pendingInAppOTP = inApp
                errorMessage = nil
                return true
            }
            errorMessage = "Could not send email and no in-app fallback is available for this address."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func friendlyOTPError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("rate limit") || message.contains("too many") {
            return "Too many sign-in attempts. Wait a few minutes and try again."
        }
        if message.contains("email") || message.contains("smtp") {
            return "Could not send the sign-in email. Check your address and try again."
        }
        return error.localizedDescription
    }
}
