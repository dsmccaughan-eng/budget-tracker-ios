import Foundation
import Supabase

extension SupabaseService {
    func fetchSavingsGoals(client: SupabaseClient) async throws -> [SavingsGoal] {
        let session = try await client.auth.session
        return try await client
            .from("savings_goals")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func saveSavingsGoal(_ goal: SavingsGoal, client: SupabaseClient) async throws -> SavingsGoal {
        let session = try await client.auth.session
        let row = SavingsGoalInsert(userId: session.user.id, goal: goal)
        let saved: SavingsGoal = try await client
            .from("savings_goals")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
        return saved
    }

    func updateSavingsGoal(_ goal: SavingsGoal, client: SupabaseClient) async throws {
        let patch = SavingsGoalPatch(goal: goal)
        try await client
            .from("savings_goals")
            .update(patch)
            .eq("id", value: goal.id.uuidString)
            .execute()
    }

    func deleteSavingsGoal(id: UUID, client: SupabaseClient) async throws {
        try await client
            .from("savings_goals")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

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

    func fetchPriceHistory(client: SupabaseClient) async throws -> [PriceHistoryItem] {
        let session = try await client.auth.session
        return try await client
            .from("price_history")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .order("date", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    func savePriceHistoryItems(_ items: [PriceHistoryItem], client: SupabaseClient) async throws {
        guard !items.isEmpty else { return }
        let session = try await client.auth.session
        let rows = items.map { PriceHistoryInsert(userId: session.user.id, item: $0) }
        try await client.from("price_history").insert(rows).execute()
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

private struct SavingsGoalInsert: Encodable {
    let userId: UUID
    let name: String
    let targetAmount: Double
    let currentAmount: Double
    let monthlyContribution: Double
    let targetDate: String?
    let linkedAccountId: UUID?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case name, emoji
        case userId = "user_id"
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case monthlyContribution = "monthly_contribution"
        case targetDate = "target_date"
        case linkedAccountId = "linked_account_id"
    }

    init(userId: UUID, goal: SavingsGoal) {
        self.userId = userId
        name = goal.name
        targetAmount = goal.targetAmount
        currentAmount = goal.currentAmount
        monthlyContribution = goal.monthlyContribution
        targetDate = goal.targetDate
        linkedAccountId = goal.linkedAccountId
        emoji = goal.emoji
    }
}

private struct SavingsGoalPatch: Encodable {
    let name: String
    let targetAmount: Double
    let currentAmount: Double
    let monthlyContribution: Double
    let targetDate: String?
    let linkedAccountId: UUID?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case name, emoji
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case monthlyContribution = "monthly_contribution"
        case targetDate = "target_date"
        case linkedAccountId = "linked_account_id"
    }

    init(goal: SavingsGoal) {
        name = goal.name
        targetAmount = goal.targetAmount
        currentAmount = goal.currentAmount
        monthlyContribution = goal.monthlyContribution
        targetDate = goal.targetDate
        linkedAccountId = goal.linkedAccountId
        emoji = goal.emoji
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

private struct PriceHistoryInsert: Encodable {
    let userId: UUID
    let itemName: String
    let price: Double
    let merchant: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case price, merchant, date
        case userId = "user_id"
        case itemName = "item_name"
    }

    init(userId: UUID, item: PriceHistoryItem) {
        self.userId = userId
        itemName = item.itemName
        price = item.price
        merchant = item.merchant
        date = item.date
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
