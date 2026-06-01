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

    /// Shown on the OTP screen when email delivery failed but edge function returned a code.
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
            throw BudgetTrackerError.server(Self.missingBackendMessage)
        }

        let created = try SupabaseClientFactory.makeClient(url: url, anonKey: SupabaseConfig.anonKey)
        client = created
        return created
    }

    static let missingBackendMessage =
        "Add your Supabase anon key below (Dashboard → Settings → API → anon public)."

    func bootstrap() async {
        errorMessage = nil
        client = nil
        pendingInAppOTP = nil

        guard SupabaseConfig.isConfigured else {
            userId = nil
            state = .unauthenticated
            errorMessage = Self.missingBackendMessage
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

    func sendOTP(email: String) async {
        errorMessage = nil
        pendingInAppOTP = nil
        client = nil

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard SupabaseConfig.isConfigured else {
            state = .unauthenticated
            errorMessage = Self.missingBackendMessage
            return
        }

        do {
            let activeClient = try makeClient()
            try await activeClient.auth.signInWithOTP(
                email: normalized,
                redirectTo: nil,
                shouldCreateUser: true
            )
        } catch {
            if await handleOTPDeliveryFallback(email: normalized, error: error) {
                return
            }
            client = nil
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func verifyOTP(email: String, token: String) async {
        errorMessage = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SupabaseConfig.isConfigured else {
            errorMessage = Self.missingBackendMessage
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

    var accessToken: String? {
        get async {
            guard let client else { return nil }
            return try? await client.auth.session.accessToken
        }
    }

    private func handleOTPDeliveryFallback(email: String, error: Error) async -> Bool {
        let message = error.localizedDescription.lowercased()
        let emailLikelyFailed = message.contains("email") || message.contains("smtp") || message.contains("500")
        guard emailLikelyFailed else { return false }

        do {
            if let inApp = try await AuthOTPBridge.requestInAppOTP(email: email) {
                pendingInAppOTP = inApp
                return true
            }
        } catch {
            errorMessage = error.localizedDescription
            return true
        }
        return false
    }
}
