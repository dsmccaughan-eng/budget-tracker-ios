import Foundation
import Supabase

enum SupabaseConfig {
    static var url: URL? {
        URL(string: APIKeys.supabaseURL)
    }

    static var anonKey: String { APIKeys.supabaseAnonKey }
    static var isConfigured: Bool { url != nil && hasValidSupabaseConfig }

    private static var hasValidSupabaseConfig: Bool {
        APIKeys.hasValidSupabaseConfig
    }
}

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

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        if let client {
            self.client = client
        } else if let url = SupabaseConfig.url, SupabaseConfig.isConfigured {
            self.client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: SupabaseConfig.anonKey
            )
        } else {
            self.client = SupabaseClient(
                supabaseURL: URL(string: "https://placeholder.supabase.co")!,
                supabaseKey: "placeholder"
            )
        }
    }

    func bootstrap() async {
        do {
            let session = try await client.auth.session
            userId = session.user.id.uuidString
            state = .authenticated
        } catch {
            userId = nil
            state = .unauthenticated
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            userId = session.user.id.uuidString
            state = .authenticated
        } catch {
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                userId = session.user.id.uuidString
                state = .authenticated
            } else {
                errorMessage = "Check your email to confirm your account."
                state = .unauthenticated
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        userId = nil
        state = .unauthenticated
    }

    var accessToken: String? {
        get async {
            try? await client.auth.session.accessToken
        }
    }

    var supabaseClient: SupabaseClient { client }
}
