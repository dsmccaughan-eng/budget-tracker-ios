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
        "Other"
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
        return nil
    }

    static func matchMerchantDB(
        merchantText: String,
        merchants: [(pattern: String, category: String, subcategory: String?)]
    ) -> MerchantRuleMatch? {
        let normalized = merchantText.lowercased()
        for merchant in merchants {
            if normalized.contains(merchant.pattern.lowercased()) {
                guard BudgetCategories.isValid(merchant.category) else { continue }
                return MerchantRuleMatch(category: merchant.category, subcategory: merchant.subcategory)
            }
        }
        return nil
    }
}
