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
}

struct MerchantRuleDraft {
    var merchantContains = ""
    var category = BudgetCategories.all.first ?? "Other"
    var subcategory: String?
}

@MainActor
final class PriceHistoryStore: ObservableObject {
    @Published private(set) var items: [PriceHistoryItem] = []
    @Published var errorMessage: String?

    func reload(client: SupabaseClient) async {
        errorMessage = nil
        do {
            items = try await SupabaseService.shared.fetchPriceHistory(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addItems(_ newItems: [PriceHistoryItem], client: SupabaseClient) async {
        guard !newItems.isEmpty else { return }
        errorMessage = nil
        do {
            try await SupabaseService.shared.savePriceHistoryItems(newItems, client: client)
            items.insert(contentsOf: newItems, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class InsightsStore: ObservableObject {
    @Published private(set) var latestInsight: FinanceInsightResult?
    @Published private(set) var subscriptions: [SubscriptionCharge] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refreshLocal(transactions: [Transaction]) {
        subscriptions = SubscriptionAuditEngine.recurringCharges(transactions: transactions)
    }

    func generateWeeklyInsight(
        transactions: [Transaction],
        budgets: [Budget],
        progress: [BudgetProgress]
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let spendByCategory = Dictionary(grouping: transactions, by: \.category)
            .mapValues { $0.reduce(0) { $0 + abs($1.amount) } }
        let budgetJSON = budgets.map { ["category": $0.category, "limit": $0.monthlyLimit] }
        let payload: [String: Any] = [
            "spendingThisWeek": spendByCategory,
            "budgetLimits": budgetJSON,
            "budgetProgress": progress.map { ["category": $0.category, "spent": $0.spent] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            errorMessage = GeminiServiceError.invalidResponse.localizedDescription
            return
        }

        do {
            latestInsight = try await GeminiService.shared.weeklyInsights(payloadJSON: json)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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
