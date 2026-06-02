import Foundation

/// Detects internal transfers and credit-card payments before merchant substring matching.
/// Prevents false positives like `mobil` (gas) matching inside `mobile credit card`.
enum TransferHeuristics {
    private static let substringPatterns = [
        "credit card payment",
        "credit card transfer",
        "mobile credit card",
        "card payment",
        "card autopay",
        "autopay payment",
        "online payment",
        "payment thank you",
        "thank you payment",
        "payoff",
        "bill pay",
        "bill payment",
        "loan payment",
        "mortgage payment",
        "ach payment",
        "ach debit",
        "ach credit",
        "wire transfer",
        "internal transfer",
        "transfer to",
        "transfer from",
        "xfer",
        "p2p transfer",
        "payment to chase",
        "payment to capital one",
        "payment to amex",
        "payment to citi",
        "payment to discover",
        "payment to bank of america",
        "payment to wells fargo",
        "payment to usaa",
        "apple cash",
        "cash advance",
    ]

    static func looksLikeTransfer(merchantText: String, plaidCategory: String? = nil) -> Bool {
        let text = merchantText.lowercased()
        if substringPatterns.contains(where: { text.contains($0) }) {
            return true
        }
        if text.contains("mobile"), text.contains("credit"), text.contains("card") {
            return true
        }
        if text.contains("credit card"), text.contains("payment") || text.contains("transfer") {
            return true
        }
        if let plaidCategory, mapPlaidHintsTransfer(plaidCategory) {
            return true
        }
        return false
    }

    static func mapPlaidHintsTransfer(_ raw: String) -> Bool {
        let key = raw.uppercased().replacingOccurrences(of: " ", with: "_")
        if key.contains("TRANSFER") { return true }
        if key.contains("CREDIT_CARD") { return true }
        if key.contains("LOAN_PAYMENT") { return true }
        return false
    }
}
