struct ExchangeTokenBody: Encodable {
    let publicToken: String
    let institutionName: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionName = "institution_name"
    }
}

struct UpdateLinkTokenBody: Encodable {
    let plaidItemId: String

    enum CodingKeys: String, CodingKey {
        case plaidItemId = "plaid_item_id"
    }
}

struct RemovePlaidItemBody: Encodable {
    let plaidItemId: String

    enum CodingKeys: String, CodingKey {
        case plaidItemId = "plaid_item_id"
    }
}

struct RemovePlaidItemResponse: Decodable {
    let removed: Bool
}

struct PlaidItem: Codable, Identifiable, Hashable {
    var id: UUID
    var plaidItemId: String
    var institutionName: String?
    var status: String
    var errorCode: String?
    var errorMessage: String?
    var lastSyncAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case plaidItemId = "plaid_item_id"
        case institutionName = "institution_name"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case lastSyncAt = "last_sync_at"
    }

    var needsReconnect: Bool {
        status == "login_required" || status == "error" || status == "pending_disconnect"
    }
}
