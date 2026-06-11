import Foundation

struct LinkPolicyResponse: Decodable {
    let provider: AggregationProvider
    let plaidItemCount: Int
    let plaidTrialLimit: Int
    let tellerConfigured: Bool
    let plaid: LinkPolicyPlaidConfig?
    let teller: LinkPolicyTellerConfig?

    enum CodingKeys: String, CodingKey {
        case provider
        case plaidItemCount = "plaid_item_count"
        case plaidTrialLimit = "plaid_trial_limit"
        case tellerConfigured = "teller_configured"
        case plaid, teller
    }

    init(
        provider: AggregationProvider,
        plaidItemCount: Int,
        plaidTrialLimit: Int,
        tellerConfigured: Bool,
        plaid: LinkPolicyPlaidConfig?,
        teller: LinkPolicyTellerConfig?
    ) {
        self.provider = provider
        self.plaidItemCount = plaidItemCount
        self.plaidTrialLimit = plaidTrialLimit
        self.tellerConfigured = tellerConfigured
        self.plaid = plaid
        self.teller = teller
    }

    static func plaidFallback(plaidItemCount: Int) -> LinkPolicyResponse {
        LinkPolicyResponse(
            provider: .plaid,
            plaidItemCount: plaidItemCount,
            plaidTrialLimit: ConnectionPolicyEngine.defaultPlaidTrialLimit,
            tellerConfigured: false,
            plaid: nil,
            teller: nil
        )
    }
}

struct LinkPolicyPlaidConfig: Decodable {
    let environment: String
}

struct LinkPolicyTellerConfig: Decodable {
    let applicationId: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case applicationId = "application_id"
        case environment
    }
}

struct TellerItem: Codable, Identifiable, Hashable {
    var id: UUID
    var tellerEnrollmentId: String
    var institutionName: String?
    var status: String
    var errorCode: String?
    var errorMessage: String?
    var lastSyncAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case tellerEnrollmentId = "teller_enrollment_id"
        case institutionName = "institution_name"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case lastSyncAt = "last_sync_at"
    }

    var needsReconnect: Bool {
        status == "login_required" || status == "disconnected" || status == "error"
    }
}

struct BankConnection: Identifiable, Hashable {
    enum Provider: String, Hashable {
        case plaid
        case teller
    }

    let id: String
    let provider: Provider
    let institutionName: String?
    let status: String
    let errorMessage: String?
    let needsReconnect: Bool
    let plaidItemId: String?
    let tellerEnrollmentId: String?

    static func from(plaid item: PlaidItem) -> BankConnection {
        BankConnection(
            id: "plaid:\(item.plaidItemId)",
            provider: .plaid,
            institutionName: item.institutionName,
            status: item.status,
            errorMessage: item.errorMessage,
            needsReconnect: item.needsReconnect,
            plaidItemId: item.plaidItemId,
            tellerEnrollmentId: nil
        )
    }

    static func from(teller item: TellerItem) -> BankConnection {
        BankConnection(
            id: "teller:\(item.tellerEnrollmentId)",
            provider: .teller,
            institutionName: item.institutionName,
            status: item.status,
            errorMessage: item.errorMessage,
            needsReconnect: item.needsReconnect,
            plaidItemId: nil,
            tellerEnrollmentId: item.tellerEnrollmentId
        )
    }
}

struct ExchangeTellerEnrollmentBody: Encodable {
    let accessToken: String
    let enrollmentId: String
    let institutionName: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case enrollmentId = "enrollment_id"
        case institutionName = "institution_name"
    }
}

struct ExchangeTellerEnrollmentResponse: Decodable {
    let enrollmentId: String
    let accountsLinked: Int
    let synced: Int

    enum CodingKeys: String, CodingKey {
        case enrollmentId = "enrollment_id"
        case accountsLinked = "accounts_linked"
        case synced
    }
}

struct RemoveTellerItemBody: Encodable {
    let tellerEnrollmentId: String

    enum CodingKeys: String, CodingKey {
        case tellerEnrollmentId = "teller_enrollment_id"
    }
}

struct RemoveTellerItemResponse: Decodable {
    let removed: Bool
}
