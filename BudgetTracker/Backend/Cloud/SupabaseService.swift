import Foundation
import Supabase

enum BudgetTrackerError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in required."
        case .invalidResponse: return "Unexpected server response."
        case .server(let message): return message
        }
    }
}

actor SupabaseService {
    static let shared = SupabaseService()

    func invokeFunction<T: Decodable>(
        name: String,
        client: SupabaseClient
    ) async throws -> T {
        try await invokeFunction(name: name, body: EmptyFunctionBody(), client: client)
    }

    func invokeFunction<T: Decodable, B: Encodable>(
        name: String,
        body: B,
        client: SupabaseClient
    ) async throws -> T {
        let session = try await client.auth.session
        let response: T = try await client.functions.invoke(
            name,
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: body
            )
        )
        return response
    }

    func fetchAccounts(client: SupabaseClient) async throws -> [Account] {
        let session = try await client.auth.session
        let rows: [Account] = try await client
            .from("accounts")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
            .value
        return rows
    }

    func fetchTransactions(client: SupabaseClient, limit: Int = 100) async throws -> [Transaction] {
        let session = try await client.auth.session
        let rows: [Transaction] = try await client
            .from("transactions")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("date", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows
    }

    func fetchBudgets(client: SupabaseClient) async throws -> [Budget] {
        let session = try await client.auth.session
        let rows: [Budget] = try await client
            .from("budgets")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
            .value
        return rows
    }

    func fetchPlaidItems(client: SupabaseClient) async throws -> [PlaidItem] {
        let session = try await client.auth.session
        let rows: [PlaidItem] = try await client
            .from("plaid_items")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }
}

struct LinkTokenResponse: Decodable {
    let linkToken: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
    }
}

struct ExchangeTokenResponse: Decodable {
    let itemId: String
    let accountsLinked: Int

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case accountsLinked = "accounts_linked"
    }
}

struct SyncTransactionsResponse: Decodable {
    let synced: Int
    let categorized: Int
}

struct EmptyFunctionBody: Encodable {}

struct PlaidAccountsFunctionResponse: Decodable {
    let accounts: [PlaidAccountSummary]?
}

struct PlaidAccountSummary: Decodable {
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
    }
}
