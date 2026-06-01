import Foundation
import Supabase

private struct NewBudgetRow: Encodable {
    let userId: UUID
    let category: String
    let monthlyLimit: Double
    let color: String
    let isRollover: Bool
    let isFixed: Bool

    enum CodingKeys: String, CodingKey {
        case category, color
        case userId = "user_id"
        case monthlyLimit = "monthly_limit"
        case isRollover = "is_rollover"
        case isFixed = "is_fixed"
    }
}

private struct TransactionCategoryPatch: Encodable {
    let category: String
    let subcategory: String?
}

extension SupabaseService {
    func syncTransactions(client: SupabaseClient) async throws -> SyncTransactionsResponse {
        try await invokeFunction(
            name: "plaid-sync-transactions",
            body: EmptyFunctionBody(),
            client: client
        )
    }

    func refreshPlaidAccounts(client: SupabaseClient) async throws {
        let _: PlaidAccountsFunctionResponse = try await invokeFunction(
            name: "plaid-get-accounts",
            body: EmptyFunctionBody(),
            client: client
        )
    }

    func createUpdateLinkToken(plaidItemId: String, client: SupabaseClient) async throws -> LinkTokenResponse {
        try await invokeFunction(
            name: "plaid-create-update-link-token",
            body: UpdateLinkTokenBody(plaidItemId: plaidItemId),
            client: client
        )
    }

    func removePlaidItem(plaidItemId: String, client: SupabaseClient) async throws {
        let _: RemovePlaidItemResponse = try await invokeFunction(
            name: "plaid-remove-item",
            body: RemovePlaidItemBody(plaidItemId: plaidItemId),
            client: client
        )
    }

    func saveBudget(_ budget: Budget, client: SupabaseClient) async throws -> Budget {
        let session = try await client.auth.session
        let row = NewBudgetRow(
            userId: session.user.id,
            category: budget.category,
            monthlyLimit: budget.monthlyLimit,
            color: budget.color,
            isRollover: budget.isRollover,
            isFixed: budget.isFixed
        )
        let saved: Budget = try await client
            .from("budgets")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
        return saved
    }

    func deleteBudget(id: UUID, client: SupabaseClient) async throws {
        try await client
            .from("budgets")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func updateTransactionCategory(
        id: UUID,
        category: String,
        subcategory: String?,
        client: SupabaseClient
    ) async throws {
        let patch = TransactionCategoryPatch(category: category, subcategory: subcategory)
        try await client
            .from("transactions")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
