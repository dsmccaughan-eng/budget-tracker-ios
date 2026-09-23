import Foundation

struct InvestmentSecurity: Codable, Identifiable, Hashable {
    var id: UUID
    var plaidSecurityId: String
    var name: String
    var tickerSymbol: String?
    var type: String?
    var subtype: String?
    var closePrice: Double?
    var closePriceAsOf: String?
    var isoCurrencyCode: String

    enum CodingKeys: String, CodingKey {
        case id, name, type, subtype
        case plaidSecurityId = "plaid_security_id"
        case tickerSymbol = "ticker_symbol"
        case closePrice = "close_price"
        case closePriceAsOf = "close_price_as_of"
        case isoCurrencyCode = "iso_currency_code"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        plaidSecurityId = try container.decode(String.self, forKey: .plaidSecurityId)
        name = try container.decode(String.self, forKey: .name)
        tickerSymbol = try container.decodeIfPresent(String.self, forKey: .tickerSymbol)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        closePrice = InvestmentJSON.decodeFlexibleDouble(container, forKey: .closePrice)
        closePriceAsOf = try container.decodeIfPresent(String.self, forKey: .closePriceAsOf)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode) ?? "USD"
    }
}

struct InvestmentHolding: Codable, Identifiable, Hashable {
    var id: UUID
    var accountId: UUID
    var securityId: UUID?
    var plaidSecurityId: String
    var quantity: Double
    var institutionPrice: Double?
    var institutionValue: Double?
    var costBasis: Double?
    var isoCurrencyCode: String

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case accountId = "account_id"
        case securityId = "security_id"
        case plaidSecurityId = "plaid_security_id"
        case institutionPrice = "institution_price"
        case institutionValue = "institution_value"
        case costBasis = "cost_basis"
        case isoCurrencyCode = "iso_currency_code"
    }

    init(
        id: UUID,
        accountId: UUID,
        securityId: UUID?,
        plaidSecurityId: String,
        quantity: Double,
        institutionPrice: Double?,
        institutionValue: Double?,
        costBasis: Double?,
        isoCurrencyCode: String
    ) {
        self.id = id
        self.accountId = accountId
        self.securityId = securityId
        self.plaidSecurityId = plaidSecurityId
        self.quantity = quantity
        self.institutionPrice = institutionPrice
        self.institutionValue = institutionValue
        self.costBasis = costBasis
        self.isoCurrencyCode = isoCurrencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        accountId = try container.decode(UUID.self, forKey: .accountId)
        securityId = try container.decodeIfPresent(UUID.self, forKey: .securityId)
        plaidSecurityId = try container.decode(String.self, forKey: .plaidSecurityId)
        quantity = InvestmentJSON.decodeFlexibleDouble(container, forKey: .quantity) ?? 0
        institutionPrice = InvestmentJSON.decodeFlexibleDouble(container, forKey: .institutionPrice)
        institutionValue = InvestmentJSON.decodeFlexibleDouble(container, forKey: .institutionValue)
        costBasis = InvestmentJSON.decodeFlexibleDouble(container, forKey: .costBasis)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode) ?? "USD"
    }
}

struct InvestmentTransaction: Codable, Identifiable, Hashable {
    var id: UUID
    var accountId: UUID
    var securityId: UUID?
    var plaidInvestmentTransactionId: String
    var plaidAccountId: String
    var plaidSecurityId: String?
    var name: String
    var type: String?
    var subtype: String?
    var date: String
    var quantity: Double?
    var amount: Double
    var price: Double?
    var fees: Double?
    var isoCurrencyCode: String

    enum CodingKeys: String, CodingKey {
        case id, name, type, subtype, date, quantity, amount, price, fees
        case accountId = "account_id"
        case securityId = "security_id"
        case plaidInvestmentTransactionId = "plaid_investment_transaction_id"
        case plaidAccountId = "plaid_account_id"
        case plaidSecurityId = "plaid_security_id"
        case isoCurrencyCode = "iso_currency_code"
    }

    init(
        id: UUID,
        accountId: UUID,
        securityId: UUID?,
        plaidInvestmentTransactionId: String,
        plaidAccountId: String,
        plaidSecurityId: String?,
        name: String,
        type: String?,
        subtype: String?,
        date: String,
        quantity: Double?,
        amount: Double,
        price: Double?,
        fees: Double?,
        isoCurrencyCode: String
    ) {
        self.id = id
        self.accountId = accountId
        self.securityId = securityId
        self.plaidInvestmentTransactionId = plaidInvestmentTransactionId
        self.plaidAccountId = plaidAccountId
        self.plaidSecurityId = plaidSecurityId
        self.name = name
        self.type = type
        self.subtype = subtype
        self.date = date
        self.quantity = quantity
        self.amount = amount
        self.price = price
        self.fees = fees
        self.isoCurrencyCode = isoCurrencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        accountId = try container.decode(UUID.self, forKey: .accountId)
        securityId = try container.decodeIfPresent(UUID.self, forKey: .securityId)
        plaidInvestmentTransactionId = try container.decode(String.self, forKey: .plaidInvestmentTransactionId)
        plaidAccountId = try container.decode(String.self, forKey: .plaidAccountId)
        plaidSecurityId = try container.decodeIfPresent(String.self, forKey: .plaidSecurityId)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        date = InvestmentJSON.decodeFlexibleDate(container, forKey: .date)
        quantity = InvestmentJSON.decodeFlexibleDouble(container, forKey: .quantity)
        amount = InvestmentJSON.decodeFlexibleDouble(container, forKey: .amount) ?? 0
        price = InvestmentJSON.decodeFlexibleDouble(container, forKey: .price)
        fees = InvestmentJSON.decodeFlexibleDouble(container, forKey: .fees)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode) ?? "USD"
    }
}

struct InvestmentSyncResponse: Decodable {
    let holdings: Int
    let transactions: Int
    let itemsProcessed: Int
    let skippedItems: Int

    enum CodingKeys: String, CodingKey {
        case holdings, transactions
        case itemsProcessed = "items_processed"
        case skippedItems = "skipped_items"
    }
}

enum InvestmentJSON {
    static func decodeFlexibleDouble<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key),
           let value = Double(text) {
            return value
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        return nil
    }

    static func decodeFlexibleDate<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String {
        if let text = try? container.decode(String.self, forKey: key) {
            return String(text.prefix(10))
        }
        return ""
    }
}
