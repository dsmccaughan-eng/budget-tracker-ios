import Foundation

enum AggregationProvider: String, Codable, Equatable {
    case plaid
    case teller
}

enum ConnectionPolicyEngine {
    static let defaultPlaidTrialLimit = 10

    /// Prefer Plaid in sandbox and while under the global Trial item cap; otherwise Teller when configured.
    static func preferredProvider(
        plaidEnvironment: String,
        globalPlaidItemCount: Int,
        plaidTrialLimit: Int = defaultPlaidTrialLimit,
        tellerConfigured: Bool
    ) -> AggregationProvider {
        guard tellerConfigured else { return .plaid }
        if plaidEnvironment.lowercased() == "sandbox" { return .plaid }
        if globalPlaidItemCount < plaidTrialLimit { return .plaid }
        return .teller
    }
}
