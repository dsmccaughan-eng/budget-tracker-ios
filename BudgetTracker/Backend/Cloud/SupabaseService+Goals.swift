import Foundation
import Supabase

extension SupabaseService {
    func fetchNetWorthSnapshots(client: SupabaseClient) async throws -> [NetWorthSnapshot] {
        let session = try await client.auth.session
        return try await client
            .from("net_worth_snapshots")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("date", ascending: false)
            .limit(500)
            .execute()
            .value
    }

    func saveNetWorthSnapshot(_ snapshot: NetWorthSnapshot, client: SupabaseClient) async throws -> NetWorthSnapshot {
        let session = try await client.auth.session
        let row = NetWorthInsert(userId: session.user.id, snapshot: snapshot)
        let saved: NetWorthSnapshot = try await client
            .from("net_worth_snapshots")
            .upsert(row, onConflict: "user_id,date")
            .select()
            .single()
            .execute()
            .value
        return saved
    }

    func fetchMerchantRules(client: SupabaseClient) async throws -> [MerchantRule] {
        let session = try await client.auth.session
        return try await client
            .from("merchant_rules")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func saveMerchantRule(_ rule: MerchantRule, client: SupabaseClient) async throws -> MerchantRule {
        let session = try await client.auth.session
        let row = MerchantRuleInsert(userId: session.user.id, rule: rule)
        return try await client
            .from("merchant_rules")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func updateMerchantRule(_ rule: MerchantRule, client: SupabaseClient) async throws -> MerchantRule {
        struct Patch: Encodable {
            let category: String
            let subcategory: String?

            enum CodingKeys: String, CodingKey {
                case category, subcategory
            }
        }
        let patch = Patch(category: rule.category, subcategory: rule.subcategory)
        return try await client
            .from("merchant_rules")
            .update(patch)
            .eq("id", value: rule.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteMerchantRule(id: UUID, client: SupabaseClient) async throws {
        try await client.from("merchant_rules").delete().eq("id", value: id.uuidString).execute()
    }

    func saveManualTransaction(_ transaction: Transaction, client: SupabaseClient) async throws -> Transaction {
        let session = try await client.auth.session
        let row = TransactionInsert(userId: session.user.id, transaction: transaction)
        return try await client
            .from("transactions")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func updateTransactionSplits(
        id: UUID,
        splitItems: [SplitItem],
        client: SupabaseClient
    ) async throws {
        let patch = SplitItemsPatch(splitItems: splitItems)
        try await client
            .from("transactions")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }
}

private struct SplitItemsPatch: Encodable {
    let splitItems: [SplitItem]

    enum CodingKeys: String, CodingKey {
        case splitItems = "split_items"
    }
}

private struct NetWorthInsert: Encodable {
    let userId: UUID
    let date: String
    let totalAssets: Double
    let totalLiabilities: Double
    let netWorth: Double

    enum CodingKeys: String, CodingKey {
        case date
        case userId = "user_id"
        case totalAssets = "total_assets"
        case totalLiabilities = "total_liabilities"
        case netWorth = "net_worth"
    }

    init(userId: UUID, snapshot: NetWorthSnapshot) {
        self.userId = userId
        date = snapshot.date
        totalAssets = snapshot.totalAssets
        totalLiabilities = snapshot.totalLiabilities
        netWorth = snapshot.netWorth
    }
}

private struct MerchantRuleInsert: Encodable {
    let userId: UUID
    let merchantContains: String
    let category: String
    let subcategory: String?

    enum CodingKeys: String, CodingKey {
        case category, subcategory
        case userId = "user_id"
        case merchantContains = "merchant_contains"
    }

    init(userId: UUID, rule: MerchantRule) {
        self.userId = userId
        merchantContains = rule.merchantContains
        category = rule.category
        subcategory = rule.subcategory
    }
}

private struct TransactionInsert: Encodable {
    let userId: UUID
    let accountId: UUID
    let plaidTransactionId: String
    let amount: Double
    let date: String
    let merchantName: String?
    let name: String
    let category: String
    let subcategory: String?
    let pending: Bool
    let isManual: Bool

    enum CodingKeys: String, CodingKey {
        case amount, date, name, category, subcategory, pending
        case userId = "user_id"
        case accountId = "account_id"
        case plaidTransactionId = "plaid_transaction_id"
        case merchantName = "merchant_name"
        case isManual = "is_manual"
    }

    init(userId: UUID, transaction: Transaction) {
        self.userId = userId
        accountId = transaction.accountId
        plaidTransactionId = transaction.plaidTransactionId
        amount = transaction.amount
        date = transaction.date
        merchantName = transaction.merchantName
        name = transaction.name
        category = transaction.category
        subcategory = transaction.subcategory
        pending = transaction.pending
        isManual = transaction.isManual
    }
}
