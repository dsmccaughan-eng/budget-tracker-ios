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
    let categorySource: String

    enum CodingKeys: String, CodingKey {
        case category, subcategory
        case categorySource = "category_source"
    }
}

private struct TransactionBillPatch: Encodable {
    let isFixedBill: Bool
    let billNickname: String?
    let billDueDay: Int?
    let billAmount: Double?

    enum CodingKeys: String, CodingKey {
        case billNickname = "bill_nickname"
        case billDueDay = "bill_due_day"
        case billAmount = "bill_amount"
        case isFixedBill = "is_fixed_bill"
    }
}

private struct TransactionBudgetPatch: Encodable {
    let excludedFromBudget: Bool

    enum CodingKeys: String, CodingKey {
        case excludedFromBudget = "excluded_from_budget"
    }
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

    func updateBudget(_ budget: Budget, client: SupabaseClient) async throws -> Budget {
        struct BudgetPatch: Encodable {
            let monthlyLimit: Double
            let color: String
            let isRollover: Bool
            let isFixed: Bool

            enum CodingKeys: String, CodingKey {
                case color
                case monthlyLimit = "monthly_limit"
                case isRollover = "is_rollover"
                case isFixed = "is_fixed"
            }
        }
        let patch = BudgetPatch(
            monthlyLimit: budget.monthlyLimit,
            color: budget.color,
            isRollover: budget.isRollover,
            isFixed: budget.isFixed
        )
        let saved: Budget = try await client
            .from("budgets")
            .update(patch)
            .eq("id", value: budget.id.uuidString)
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

    func fetchAccountBalanceSnapshots(
        client: SupabaseClient,
        since: String
    ) async throws -> [AccountBalanceSnapshot] {
        let session = try await client.auth.session
        return try await client
            .from("account_balance_snapshots")
            .select()
            .eq("user_id", value: session.user.id.uuidString)
            .gte("date", value: since)
            .order("date", ascending: false)
            .limit(5000)
            .execute()
            .value
    }

    func upsertAccountBalanceSnapshots(
        _ snapshots: [AccountBalanceSnapshot],
        client: SupabaseClient
    ) async throws {
        guard !snapshots.isEmpty else { return }
        let session = try await client.auth.session
        struct Row: Encodable {
            let userId: UUID
            let accountId: UUID
            let date: String
            let currentBalance: Double?
            let availableBalance: Double?

            enum CodingKeys: String, CodingKey {
                case date
                case userId = "user_id"
                case accountId = "account_id"
                case currentBalance = "current_balance"
                case availableBalance = "available_balance"
            }
        }
        let rows = snapshots.map {
            Row(
                userId: session.user.id,
                accountId: $0.accountId,
                date: $0.date,
                currentBalance: $0.currentBalance,
                availableBalance: $0.availableBalance
            )
        }
        try await client
            .from("account_balance_snapshots")
            .upsert(rows, onConflict: "user_id,account_id,date")
            .execute()
    }

    func updateTransactionCategory(
        id: UUID,
        category: String,
        subcategory: String?,
        categorySource: String = CategorySource.user.rawValue,
        client: SupabaseClient
    ) async throws {
        let patch = TransactionCategoryPatch(
            category: category,
            subcategory: subcategory,
            categorySource: categorySource
        )
        try await client
            .from("transactions")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func updateTransactionBillSettings(
        id: UUID,
        isFixedBill: Bool,
        billNickname: String?,
        billDueDay: Int?,
        billAmount: Double?,
        client: SupabaseClient
    ) async throws {
        let patch = TransactionBillPatch(
            isFixedBill: isFixedBill,
            billNickname: billNickname,
            billDueDay: billDueDay,
            billAmount: billAmount
        )
        try await client
            .from("transactions")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func updateTransactionBudgetExclusion(
        id: UUID,
        excludedFromBudget: Bool,
        client: SupabaseClient
    ) async throws {
        let patch = TransactionBudgetPatch(excludedFromBudget: excludedFromBudget)
        try await client
            .from("transactions")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
