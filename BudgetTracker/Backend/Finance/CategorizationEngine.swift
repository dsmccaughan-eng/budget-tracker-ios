import Foundation

enum BudgetCategories {
    static let all: [String] = [
        "Housing & Utilities",
        "Groceries",
        "Dining & Bars",
        "Transport",
        "Shopping",
        "Health & Wellness",
        "Travel",
        "Entertainment",
        "Subscriptions",
        "Personal Care",
        "Education",
        "Pets",
        "Gifts & Donations",
        "Insurance",
        "Investments",
        "Business",
        "Income",
        "Transfers",
        "Other",
    ]

    static func isValid(_ category: String) -> Bool {
        all.contains(category)
    }
}

struct MerchantRuleMatch: Equatable {
    let category: String
    let subcategory: String?
}

enum CategorizationEngine {
    static func matchMerchantRules(
        merchantText: String,
        rules: [(contains: String, category: String, subcategory: String?)]
    ) -> MerchantRuleMatch? {
        let normalized = merchantText.lowercased()
        for rule in rules {
            if normalized.contains(rule.contains.lowercased()) {
                guard BudgetCategories.isValid(rule.category) else { continue }
                return MerchantRuleMatch(category: rule.category, subcategory: rule.subcategory)
            }
        }
        var best: MerchantRuleMatch?
        var bestScore = 0.68
        for rule in rules {
            let score = MerchantSimilarity.similarityScore(normalized, rule.contains)
            if score >= bestScore, BudgetCategories.isValid(rule.category) {
                best = MerchantRuleMatch(category: rule.category, subcategory: rule.subcategory)
                bestScore = score
            }
        }
        return best
    }

    static func matchMerchantDB(
        merchantText: String,
        merchants: [(pattern: String, category: String, subcategory: String?)]
    ) -> MerchantRuleMatch? {
        let normalized = merchantText.lowercased()
        if HousingHeuristics.looksLikeHousing(merchantText: merchantText) {
            return MerchantRuleMatch(category: "Housing & Utilities", subcategory: nil)
        }
        if TransferHeuristics.looksLikeTransfer(merchantText: merchantText) {
            return MerchantRuleMatch(category: "Transfers", subcategory: nil)
        }
        let sorted = merchants.sorted { $0.pattern.count > $1.pattern.count }
        for merchant in sorted {
            if merchant.category == "Transport",
               TransferHeuristics.shouldSkipTransportMerchantMatch(
                   merchantPattern: merchant.pattern,
                   merchantText: merchantText
               ) {
                continue
            }
            if matchesMerchantPattern(normalized, pattern: merchant.pattern.lowercased()) {
                guard BudgetCategories.isValid(merchant.category) else { continue }
                return MerchantRuleMatch(category: merchant.category, subcategory: merchant.subcategory)
            }
        }
        return nil
    }

    private static func matchesMerchantPattern(_ text: String, pattern: String) -> Bool {
        if pattern.count <= 5, !pattern.contains(" ") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return text.contains(pattern)
    }
}
