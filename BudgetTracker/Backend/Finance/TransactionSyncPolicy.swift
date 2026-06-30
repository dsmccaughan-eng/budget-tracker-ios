import Foundation

enum TransactionSyncPolicy {
    /// Minimum time between automatic client-initiated syncs (server rate limit is 12/hour).
    static let minimumClientInterval: TimeInterval = 30 * 60
    /// When server `last_sync_at` is older than this, force a sync even inside the client window.
    static let staleServerSyncInterval: TimeInterval = 6 * 60 * 60
    /// When the newest stored transaction is older than this, treat data as stale.
    static let staleTransactionInterval: TimeInterval = 48 * 60 * 60

    static func hasSyncableConnections(plaidItems: [PlaidItem], tellerItems: [TellerItem]) -> Bool {
        let hasPlaid = plaidItems.contains { item in
            item.status != "revoked" && item.status != "login_required"
        }
        let hasTeller = tellerItems.contains { item in
            item.status != "revoked" && item.status != "disconnected"
        }
        return hasPlaid || hasTeller
    }

    static func shouldSyncAutomatically(
        lastClientSyncAt: Date?,
        plaidItems: [PlaidItem],
        tellerItems: [TellerItem],
        transactions: [Transaction],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard hasSyncableConnections(plaidItems: plaidItems, tellerItems: tellerItems) else {
            return false
        }
        if lastClientSyncAt == nil {
            return true
        }
        if let lastClientSyncAt,
           now.timeIntervalSince(lastClientSyncAt) >= minimumClientInterval {
            return true
        }
        if serverSyncIsStale(plaidItems: plaidItems, tellerItems: tellerItems, now: now) {
            return true
        }
        if transactionsAppearStale(transactions: transactions, now: now, calendar: calendar) {
            return true
        }
        return false
    }

    /// Record a client sync attempt only when new rows arrived or local data is no longer stale.
    static func shouldRecordClientSync(
        syncedCount: Int,
        transactions: [Transaction],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if syncedCount > 0 { return true }
        return !transactionsAppearStale(transactions: transactions, now: now, calendar: calendar)
    }

    static func serverSyncIsStale(
        plaidItems: [PlaidItem],
        tellerItems: [TellerItem],
        now: Date
    ) -> Bool {
        var syncDates: [Date] = []

        for item in plaidItems where item.status == "active" {
            if let parsed = parseServerTimestamp(item.lastSyncAt) {
                syncDates.append(parsed)
            } else {
                return true
            }
        }

        for item in tellerItems where item.status != "revoked" && item.status != "disconnected" {
            if let parsed = parseServerTimestamp(item.lastSyncAt) {
                syncDates.append(parsed)
            } else {
                return true
            }
        }

        guard let mostRecent = syncDates.max() else { return true }
        return now.timeIntervalSince(mostRecent) >= staleServerSyncInterval
    }

    static func transactionsAppearStale(
        transactions: [Transaction],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let newest = newestTransactionDate(transactions: transactions, calendar: calendar) else {
            return false
        }
        return now.timeIntervalSince(newest) >= staleTransactionInterval
    }

    static func newestTransactionDate(
        transactions: [Transaction],
        calendar: Calendar = .current
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return transactions.compactMap { formatter.date(from: $0.date) }.max()
    }

    static func parseServerTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        if let date = fallback.date(from: raw) {
            return date
        }
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return fallback.date(from: raw)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct TransactionSyncStore {
    private let defaults: UserDefaults
    private let keyPrefix = "budgettracker.transactionSync.lastAt."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastSyncAt(userId: String) -> Date? {
        defaults.object(forKey: storageKey(userId: userId)) as? Date
    }

    func markSynced(userId: String, at date: Date) {
        defaults.set(date, forKey: storageKey(userId: userId))
    }

    private func storageKey(userId: String) -> String {
        keyPrefix + userId
    }
}
