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

    func loadAll(client: SupabaseClient, clearsError: Bool = true) async {
        if clearsError { errorMessage = nil }
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
            await loadAll(client: client, clearsError: false)
            if let errorMessage {
                lastSyncSummary = nil
                return
            }
            if result.holdings == 0, result.transactions == 0, result.skippedItems > 0 {
                lastSyncSummary =
                    "Investments not enabled for \(result.skippedItems) bank connection(s). Tap Enable holdings on Accounts for Principal/Robinhood."
                errorMessage = lastSyncSummary
            } else if result.holdings == 0, result.transactions == 0, result.itemsProcessed > 0 {
                lastSyncSummary =
                    "Bank responded but returned no holdings. Robinhood crypto is often not included by Plaid."
            } else {
                lastSyncSummary =
                    "Synced \(result.holdings) holdings and \(result.transactions) investment transactions."
            }
        } catch {
            errorMessage = error.localizedDescription
            lastSyncSummary = nil
        }
    }

    func securitiesByID() -> [UUID: InvestmentSecurity] {
        Dictionary(uniqueKeysWithValues: securities.map { ($0.id, $0) })
    }

    func holdings(for accountId: UUID) -> [InvestmentHolding] {
        holdings.filter { $0.accountId == accountId }
    }

    /// Marked-to-market total from synced holdings (often fresher than Plaid account balance).
    func holdingsMarketValue(for accountId: UUID) -> Double? {
        let rows = holdings(for: accountId)
        guard !rows.isEmpty else { return nil }
        let total = rows.reduce(0.0) { $0 + ($1.institutionValue ?? 0) }
        return total > 0 ? total : nil
    }

    func preferredBalance(for account: Account) -> Double? {
        let plaid = account.currentBalance
        guard let holdingsValue = holdingsMarketValue(for: account.id) else {
            return plaid
        }
        guard let plaid else { return holdingsValue }
        return max(plaid, holdingsValue)
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

    /// Test helper — not used by production UI.
    func replaceHoldingsForTests(_ value: [InvestmentHolding]) {
        holdings = value
    }
}
