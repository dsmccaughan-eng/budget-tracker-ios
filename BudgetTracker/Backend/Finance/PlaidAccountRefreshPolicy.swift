import Foundation

enum PlaidAccountRefreshPolicy {
    static func hasRefreshablePlaidItems(_ items: [PlaidItem]) -> Bool {
        items.contains { $0.status != "revoked" }
    }

    /// Returns true when no refresh has been recorded yet or the last refresh was on a prior calendar day.
    static func shouldRefreshAutomatically(
        lastRefreshAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastRefreshAt else { return true }
        return !calendar.isDate(lastRefreshAt, inSameDayAs: now)
    }
}

struct PlaidAccountRefreshStore {
    private let defaults: UserDefaults
    private let keyPrefix = "budgettracker.plaid.accountRefresh.lastAt."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastRefreshAt(userId: String) -> Date? {
        defaults.object(forKey: storageKey(userId: userId)) as? Date
    }

    func markRefreshed(userId: String, at date: Date) {
        defaults.set(date, forKey: storageKey(userId: userId))
    }

    private func storageKey(userId: String) -> String {
        keyPrefix + userId
    }
}
