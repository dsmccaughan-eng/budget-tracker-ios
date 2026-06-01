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

    private var client: SupabaseClient?

    init(injectedClient: SupabaseClient? = nil) {
        client = injectedClient
    }

    /// Client available only after successful bootstrap or sign-in (avoids launch-time traps).
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
            throw BudgetTrackerError.server("Missing backend configuration. Add Supabase keys in Settings.")
        }

        let created = try SupabaseClientFactory.makeClient(url: url, anonKey: SupabaseConfig.anonKey)
        client = created
        return created
    }

    func bootstrap() async {
        errorMessage = nil
        client = nil

        guard SupabaseConfig.isConfigured else {
            userId = nil
            state = .unauthenticated
            errorMessage = "Missing backend configuration. Add Supabase keys in Settings."
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

    func signIn(email: String, password: String) async {
        errorMessage = nil
        client = nil

        guard SupabaseConfig.isConfigured else {
            state = .unauthenticated
            errorMessage = "Missing backend configuration. Add Supabase keys in Settings."
            return
        }

        do {
            let activeClient = try makeClient()
            let session = try await activeClient.auth.signIn(email: email, password: password)
            userId = session.user.id.uuidString
            state = .authenticated
        } catch {
            client = nil
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        client = nil

        guard SupabaseConfig.isConfigured else {
            state = .unauthenticated
            errorMessage = "Missing backend configuration. Add Supabase keys in Settings."
            return
        }

        do {
            let activeClient = try makeClient()
            let response = try await activeClient.auth.signUp(email: email, password: password)
            if let session = response.session {
                userId = session.user.id.uuidString
                state = .authenticated
            } else {
                client = nil
                errorMessage = "Check your email to confirm your account."
                state = .unauthenticated
            }
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
        state = .unauthenticated
    }

    var accessToken: String? {
        get async {
            guard let client else { return nil }
            return try? await client.auth.session.accessToken
        }
    }
}
