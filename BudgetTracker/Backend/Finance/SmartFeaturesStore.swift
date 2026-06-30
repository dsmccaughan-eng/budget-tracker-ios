import Foundation
import Supabase
import UserNotifications

@MainActor
final class MerchantRulesStore: ObservableObject {
    @Published private(set) var rules: [MerchantRule] = []
    @Published var errorMessage: String?

    func reload(client: SupabaseClient) async {
        errorMessage = nil
        do {
            rules = try await SupabaseService.shared.fetchMerchantRules(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRule(_ draft: MerchantRuleDraft, client: SupabaseClient) async {
        errorMessage = nil
        let rule = MerchantRule(
            id: UUID(),
            merchantContains: draft.merchantContains,
            category: draft.category,
            subcategory: draft.subcategory
        )
        do {
            let saved = try await SupabaseService.shared.saveMerchantRule(rule, client: client)
            rules.insert(saved, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRule(_ rule: MerchantRule, client: SupabaseClient) async {
        do {
            try await SupabaseService.shared.deleteMerchantRule(id: rule.id, client: client)
            rules.removeAll { $0.id == rule.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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

struct MerchantRuleDraft {
    var merchantContains = ""
    var category = BudgetCategories.all.first ?? "Other"
    var subcategory: String?
}

@MainActor
final class NotificationSettingsStore: ObservableObject {
    @Published var budgetAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(budgetAlertsEnabled, forKey: Keys.enabled) }
    }
    @Published var alertThreshold: Double {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Keys.threshold) }
    }

    private enum Keys {
        static let enabled = "notifications.budget.enabled"
        static let threshold = "notifications.budget.threshold"
    }

    init() {
        budgetAlertsEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        alertThreshold = UserDefaults.standard.object(forKey: Keys.threshold) as? Double ?? 0.8
    }

    func scheduleBudgetAlerts(messages: [String]) {
        guard budgetAlertsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["budget-alert"])
        guard let message = messages.first else { return }
        let content = UNMutableNotificationContent()
        content.title = "Budget Tracker"
        content.body = message
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "budget-alert", content: content, trigger: trigger)
        center.add(request)
    }
}
