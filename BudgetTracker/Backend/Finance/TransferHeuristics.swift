import Foundation

/// Detects internal transfers and credit-card payments before merchant substring matching.
/// Prevents false positives like `mobil` (gas) or `metro` (transit) matching mobile banking payments.
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
        "scheduled payment",
        "payment to acct",
        "recurring from chk",
        "online/mobile recurring",
        "online/mobile",
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
        "mobile pmt",
        "mobile payment",
        "mobile pymt",
        "card pmt",
        "card pymt",
        "epayment",
        "e payment",
        "payment from chk",
        "payment from checking",
        "payment to card",
        "payment to credit",
        "cr card pmt",
        "cr card payment",
        "visa payment",
        "mastercard payment",
        "discover payment",
        "amex payment",
        "synchrony bank",
        "apple card",
    ]

    private static let mobileCarrierPatterns = [
        "t mobile",
        "t-mobile",
        "tmobile",
        "verizon wireless",
        "verizon",
        "at t wireless",
        "at&t",
        "att wireless",
        "sprint",
        "cricket wireless",
        "google fi",
        "mint mobile",
        "boost mobile",
        "us cellular",
        "metro by t-mobile",
    ]

    private static let paymentTokens = [
        "payment", "pmt", "pymt", "autopay", "payoff", "pay",
    ]

    private static let channelTokens = ["mobile", "online", "web"]

    private static let cardTokens = [
        "card", "credit", "visa", "mastercard", "discover", "amex", "synchrony",
    ]

    private static let ambiguousTransportPatterns: Set<String> = [
        "metro", "mobil", "bp", "marathon", "76", "enterprise",
    ]

    static func hasPaymentContext(merchantText: String) -> Bool {
        let normalized = MerchantSimilarity.normalizeMerchantText(merchantText)
        return paymentTokens.contains(where: { normalized.contains($0) })
    }

    static func looksLikeMobileCardPayment(merchantText: String) -> Bool {
        let lower = merchantText.lowercased()
        let normalized = MerchantSimilarity.normalizeMerchantText(merchantText)

        if mobileCarrierPatterns.contains(where: { normalized.contains($0) }) {
            return false
        }
        if normalized.contains("mobile credit card") { return true }
        if lower.contains("online/mobile") { return true }

        let hasPayment = paymentTokens.contains(where: { normalized.contains($0) })
        let hasChannel = channelTokens.contains(where: { normalized.contains($0) })
        let hasCard = cardTokens.contains(where: { normalized.contains($0) })

        if hasPayment && hasChannel { return true }
        if hasPayment && hasCard { return true }
        if hasChannel && hasCard { return true }

        if normalized.range(
            of: #"\bmobile\b.*\b(cr|credit|card|pmt|payment|xfer|transfer)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    static func shouldSkipTransportMerchantMatch(
        merchantPattern: String,
        merchantText: String
    ) -> Bool {
        let pattern = merchantPattern.lowercased()
        guard ambiguousTransportPatterns.contains(pattern) else { return false }
        return hasPaymentContext(merchantText: merchantText) ||
            looksLikeMobileCardPayment(merchantText: merchantText)
    }

    static func looksLikeTransfer(
        merchantText: String,
        plaidCategory: String? = nil,
        plaidDetailedCategory: String? = nil
    ) -> Bool {
        if mobileCarrierPatterns.contains(where: {
            MerchantSimilarity.normalizeMerchantText(merchantText).contains($0)
        }) {
            return false
        }

        let text = merchantText.lowercased()
        let normalized = MerchantSimilarity.normalizeMerchantText(merchantText)

        if substringPatterns.contains(where: { text.contains($0) }) { return true }
        if substringPatterns.contains(where: { normalized.contains($0) }) { return true }
        if looksLikeMobileCardPayment(merchantText: merchantText) { return true }
        if text.contains("mobile"), text.contains("credit"), text.contains("card") {
            return true
        }
        if text.contains("credit card"),
           text.contains("payment") || text.contains("transfer") {
            return true
        }
        for raw in [plaidDetailedCategory, plaidCategory].compactMap({ $0 }) {
            if mapPlaidHintsTransfer(raw) { return true }
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
