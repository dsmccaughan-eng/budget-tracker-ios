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
    var excludedFromBudget: Bool = false

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
        case excludedFromBudget = "excluded_from_budget"
    }
}

struct SplitItem: Codable, Hashable {
    var category: String
    var amount: Double
    var note: String?
}

struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var provider: String
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
        case id, name, type, subtype, mask, provider
        case plaidItemId = "plaid_item_id"
        case plaidAccountId = "plaid_account_id"
        case officialName = "official_name"
        case currentBalance = "current_balance"
        case availableBalance = "available_balance"
    }

    init(
        id: UUID,
        provider: String = "plaid",
        plaidItemId: String,
        plaidAccountId: String,
        name: String,
        officialName: String?,
        type: String,
        subtype: String?,
        mask: String?,
        currentBalance: Double?,
        availableBalance: Double?
    ) {
        self.id = id
        self.provider = provider
        self.plaidItemId = plaidItemId
        self.plaidAccountId = plaidAccountId
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "plaid"
        plaidItemId = try container.decodeIfPresent(String.self, forKey: .plaidItemId) ?? ""
        plaidAccountId = try container.decodeIfPresent(String.self, forKey: .plaidAccountId) ?? ""
        name = try container.decode(String.self, forKey: .name)
        officialName = try container.decodeIfPresent(String.self, forKey: .officialName)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "other"
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        mask = try container.decodeIfPresent(String.self, forKey: .mask)
        currentBalance = Self.decodeFlexibleDouble(container, forKey: .currentBalance)
        availableBalance = Self.decodeFlexibleDouble(container, forKey: .availableBalance)
    }

    private static func decodeFlexibleDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key),
           let value = Double(text) {
            return value
        }
        return nil
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
