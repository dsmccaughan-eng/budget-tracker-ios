import Foundation
import Supabase

extension SupabaseService {
    func syncPlaidInvestments(client: SupabaseClient) async throws -> InvestmentSyncResponse {
        try await invokeFunction(name: "plaid-sync-investments", client: client)
    }

    func fetchInvestmentSecurities(client: SupabaseClient) async throws -> [InvestmentSecurity] {
        let session = try await client.auth.session
        let rows: [InvestmentSecurity] = try await client
            .from("investment_securities")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("ticker_symbol", ascending: true)
            .execute()
            .value
        return rows
    }

    func fetchInvestmentHoldings(client: SupabaseClient) async throws -> [InvestmentHolding] {
        let session = try await client.auth.session
        let rows: [InvestmentHolding] = try await client
            .from("investment_holdings")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
            .value
        return rows
    }

    func fetchInvestmentTransactions(
        client: SupabaseClient,
        since: String? = nil,
        limit: Int = 5000
    ) async throws -> [InvestmentTransaction] {
        let session = try await client.auth.session
        var filter = client
            .from("investment_transactions")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
        if let since {
            filter = filter.gte("date", value: since)
        }
        let rows: [InvestmentTransaction] = try await filter
            .order("date", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows
    }
}
