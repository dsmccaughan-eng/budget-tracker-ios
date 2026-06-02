import Foundation

struct Transaction: Codable, Identifiable, Hashable {
    var id: UUID
    var accountId: UUID
    var plaidTransactionId: String
    var amount: Double
    var date: String
    var merchantName: String?
    var name: String
    var category: String
    var subcategory: String?
    var pending: Bool
    var isManual: Bool
    var splitItems: [SplitItem]?
    var categorySource: String? = nil
    var isFixedBill: Bool = false
    var billNickname: String? = nil
    var billDueDay: Int? = nil
    var billAmount: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case plaidTransactionId = "plaid_transaction_id"
        case amount, date, name, category, subcategory, pending
        case merchantName = "merchant_name"
        case isManual = "is_manual"
        case splitItems = "split_items"
        case categorySource = "category_source"
        case isFixedBill = "is_fixed_bill"
        case billNickname = "bill_nickname"
        case billDueDay = "bill_due_day"
        case billAmount = "bill_amount"
    }
}

struct SplitItem: Codable, Hashable {
    var category: String
    var amount: Double
    var note: String?
}

struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var plaidItemId: String
    var plaidAccountId: String
    var name: String
    var officialName: String?
    var type: String
    var subtype: String?
    var mask: String?
    var currentBalance: Double?
    var availableBalance: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, type, subtype, mask
        case plaidItemId = "plaid_item_id"
        case plaidAccountId = "plaid_account_id"
        case officialName = "official_name"
        case currentBalance = "current_balance"
        case availableBalance = "available_balance"
    }
}

struct Budget: Codable, Identifiable, Hashable {
    var id: UUID
    var category: String
    var monthlyLimit: Double
    var color: String
    var isRollover: Bool
    var isFixed: Bool

    enum CodingKeys: String, CodingKey {
        case id, category, color
        case monthlyLimit = "monthly_limit"
        case isRollover = "is_rollover"
        case isFixed = "is_fixed"
    }
}

struct SavingsGoal: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var monthlyContribution: Double
    var targetDate: String?
    var linkedAccountId: UUID?
    var emoji: String?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case monthlyContribution = "monthly_contribution"
        case targetDate = "target_date"
        case linkedAccountId = "linked_account_id"
    }
}

struct MerchantRule: Codable, Identifiable, Hashable {
    var id: UUID
    var merchantContains: String
    var category: String
    var subcategory: String?

    enum CodingKeys: String, CodingKey {
        case id, category, subcategory
        case merchantContains = "merchant_contains"
    }
}

struct PriceHistoryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var itemName: String
    var price: Double
    var merchant: String
    var date: String

    enum CodingKeys: String, CodingKey {
        case id, price, merchant, date
        case itemName = "item_name"
    }
}

struct NetWorthSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var date: String
    var totalAssets: Double
    var totalLiabilities: Double
    var netWorth: Double

    enum CodingKeys: String, CodingKey {
        case id, date
        case totalAssets = "total_assets"
        case totalLiabilities = "total_liabilities"
        case netWorth = "net_worth"
    }
}
