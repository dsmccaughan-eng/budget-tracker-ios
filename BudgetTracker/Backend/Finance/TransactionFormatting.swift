import Foundation
import SwiftUI

/// Plaid uses positive amounts for outflows and negative for inflows (refunds, credits).
enum TransactionFormatting {
    static func displayAmount(_ plaidAmount: Double) -> Double {
        -plaidAmount
    }

    static func isInflow(_ plaidAmount: Double) -> Bool {
        plaidAmount < 0
    }

    static func isOutflow(_ plaidAmount: Double) -> Bool {
        plaidAmount > 0
    }

    static func formattedAmount(_ plaidAmount: Double) -> String {
        let display = displayAmount(plaidAmount)
        let formatted = FinanceFormatting.currency(abs(display))
        if display > 0 { return "+\(formatted)" }
        if display < 0 { return "-\(formatted)" }
        return formatted
    }

    static func amountLabel(_ plaidAmount: Double) -> String {
        if isInflow(plaidAmount) { return "Credit" }
        if isOutflow(plaidAmount) { return "Expense" }
        return "Zero"
    }

    static func amountColor(_ plaidAmount: Double) -> Color {
        if isInflow(plaidAmount) { return .green }
        if isOutflow(plaidAmount) { return .primary }
        return .secondary
    }
}

enum CategorySource: String, Codable, CaseIterable {
    case merchantRule = "merchant_rule"
    case merchantDb = "merchant_db"
    case gemini
    case plaid
    case user
    case userSimilar = "user_similar"

    var displayLabel: String {
        switch self {
        case .merchantRule: return "Your saved rule"
        case .merchantDb: return "Known merchant"
        case .gemini: return "AI categorized"
        case .plaid: return "Bank category"
        case .user: return "You set this"
        case .userSimilar: return "Similar to your past"
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .gemini:
            return "Gemini assigned this category because no rule or bank mapping matched."
        case .userSimilar:
            return "Matched a similar merchant you categorized before."
        default:
            return nil
        }
    }

    static func from(_ raw: String?) -> CategorySource? {
        guard let raw else { return nil }
        return CategorySource(rawValue: raw)
    }
}

enum MerchantRulePattern {
    static func from(transaction: Transaction) -> String {
        let name = FinanceFormatting.displayName(for: transaction)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return transaction.name.lowercased() }
        return name
    }
}
