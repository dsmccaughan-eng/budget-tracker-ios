import Foundation
import Supabase

extension SupabaseService {
    func fetchLinkPolicy(client: SupabaseClient) async throws -> LinkPolicyResponse {
        try await invokeFunction(name: "aggregation-link-policy", client: client)
    }

    func fetchTellerItems(client: SupabaseClient) async throws -> [TellerItem] {
        let session = try await client.auth.session
        let rows: [TellerItem] = try await client
            .from("teller_items")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    func exchangeTellerEnrollment(
        accessToken: String,
        enrollmentId: String,
        institutionName: String?,
        client: SupabaseClient
    ) async throws -> ExchangeTellerEnrollmentResponse {
        try await invokeFunction(
            name: "teller-exchange-enrollment",
            body: ExchangeTellerEnrollmentBody(
                accessToken: accessToken,
                enrollmentId: enrollmentId,
                institutionName: institutionName
            ),
            client: client
        )
    }

    func removeTellerItem(tellerEnrollmentId: String, client: SupabaseClient) async throws {
        let _: RemoveTellerItemResponse = try await invokeFunction(
            name: "teller-remove-item",
            body: RemoveTellerItemBody(tellerEnrollmentId: tellerEnrollmentId),
            client: client
        )
    }

    func syncAllTransactions(client: SupabaseClient) async throws -> SyncTransactionsResponse {
        try await invokeFunction(
            name: "aggregation-sync-transactions",
            client: client
        )
    }
}
