import Foundation
import Supabase

@MainActor
final class InvestmentStore: ObservableObject {
    @Published private(set) var securities: [InvestmentSecurity] = []
    @Published private(set) var holdings: [InvestmentHolding] = []
    @Published private(set) var transactions: [InvestmentTransaction] = []
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published private(set) var lastSyncSummary: String?

    func loadAll(client: SupabaseClient) async {
        errorMessage = nil
        do {
            securities = try await SupabaseService.shared.fetchInvestmentSecurities(client: client)
            holdings = try await SupabaseService.shared.fetchInvestmentHoldings(client: client)
            transactions = try await SupabaseService.shared.fetchInvestmentTransactions(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncFromPlaid(client: SupabaseClient) async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let result = try await SupabaseService.shared.syncPlaidInvestments(client: client)
            lastSyncSummary = "Synced \(result.holdings) holdings and \(result.transactions) investment transactions."
            await loadAll(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func securitiesByID() -> [UUID: InvestmentSecurity] {
        Dictionary(uniqueKeysWithValues: securities.map { ($0.id, $0) })
    }

    func holdings(for accountId: UUID) -> [InvestmentHolding] {
        holdings.filter { $0.accountId == accountId }
    }

    func transactions(for accountId: UUID) -> [InvestmentTransaction] {
        transactions
            .filter { $0.accountId == accountId }
            .sorted { $0.date > $1.date }
    }

    func security(for holding: InvestmentHolding, lookup: [UUID: InvestmentSecurity]) -> InvestmentSecurity? {
        if let securityId = holding.securityId {
            return lookup[securityId]
        }
        return securities.first { $0.plaidSecurityId == holding.plaidSecurityId }
    }
}
