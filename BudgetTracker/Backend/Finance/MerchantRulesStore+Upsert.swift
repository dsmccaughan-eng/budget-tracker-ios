import Foundation
import Supabase

extension MerchantRulesStore {
    func upsertRule(
        for transaction: Transaction,
        category: String,
        client: SupabaseClient
    ) async throws {
        let pattern = MerchantRulePattern.from(transaction: transaction)
        guard !pattern.isEmpty else { return }

        if let existing = rules.first(where: { rule in
            let existingPattern = rule.merchantContains.lowercased()
            return existingPattern == pattern ||
                pattern.contains(existingPattern) ||
                existingPattern.contains(pattern)
        }) {
            var updated = existing
            updated.category = category
            let saved = try await SupabaseService.shared.updateMerchantRule(updated, client: client)
            if let index = rules.firstIndex(where: { $0.id == saved.id }) {
                rules[index] = saved
            }
            return
        }

        let draft = MerchantRuleDraft(
            merchantContains: pattern,
            category: category,
            subcategory: transaction.subcategory
        )
        await addRule(draft, client: client)
        if errorMessage != nil {
            throw BudgetTrackerError.server(errorMessage ?? "Could not save merchant rule.")
        }
    }
}
