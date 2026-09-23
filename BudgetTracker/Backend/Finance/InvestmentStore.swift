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
                let holdingsTotals = holdingsMarketValuesByAccountId()
                if holdingsTotals.isEmpty {
                    lastSyncSummary =
                        "Synced \(result.holdings) holdings and \(result.transactions) investment transactions."
                } else {
                    lastSyncSummary =
                        "Synced \(result.holdings) holdings. Account balances updated from holdings market value."
                }
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
        // When holdings exist, they are the marked-to-market source of truth for
        // retirement/brokerage (Plaid /accounts/get is often months stale).
        if let holdingsValue = holdingsMarketValue(for: account.id) {
            return holdingsValue
        }
        return account.currentBalance
    }

    /// Per-account holdings totals for patching account rows after sync.
    func holdingsMarketValuesByAccountId() -> [UUID: Double] {
        var totals: [UUID: Double] = [:]
        for holding in holdings {
            guard let value = holding.institutionValue, value != 0 else { continue }
            totals[holding.accountId, default: 0] += value
        }
        return totals.filter { $0.value > 0 }
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
