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
        closePrice = Self.decodeFlexibleDouble(container, forKey: .closePrice)
        closePriceAsOf = try container.decodeIfPresent(String.self, forKey: .closePriceAsOf)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode) ?? "USD"
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
