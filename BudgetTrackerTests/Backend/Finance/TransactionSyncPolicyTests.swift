import XCTest
@testable import BudgetTracker

final class TransactionSyncPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testHasSyncableConnectionsIgnoresLoginRequiredPlaidItems() {
        let item = PlaidItem(
            id: UUID(),
            plaidItemId: "item_1",
            institutionName: "Bank",
            status: "login_required",
            errorCode: nil,
            errorMessage: nil,
            lastSyncAt: nil
        )
        XCTAssertFalse(TransactionSyncPolicy.hasSyncableConnections(plaidItems: [item], tellerItems: []))
    }

    func testShouldSyncWhenNeverSyncedClientSide() {
        let item = activePlaidItem(lastSyncAt: "2026-06-10T12:00:00Z")
        XCTAssertTrue(
            TransactionSyncPolicy.shouldSyncAutomatically(
                lastClientSyncAt: nil,
                plaidItems: [item],
                tellerItems: [],
                transactions: [],
                now: date("2026-06-10", hour: 13),
                calendar: calendar
            )
        )
    }

    func testShouldSyncAfterMinimumClientInterval() {
        let item = activePlaidItem(lastSyncAt: "2026-06-10T12:00:00Z")
        let lastClient = date("2026-06-10", hour: 8)
        let now = date("2026-06-10", hour: 9)
        XCTAssertTrue(
            TransactionSyncPolicy.shouldSyncAutomatically(
                lastClientSyncAt: lastClient,
                plaidItems: [item],
                tellerItems: [],
                transactions: [],
                now: now,
                calendar: calendar
            )
        )
    }

    func testShouldNotSyncInsideClientIntervalWhenServerFresh() {
        let item = activePlaidItem(lastSyncAt: "2026-06-10T12:00:00Z")
        let lastClient = date("2026-06-10", hour: 12, minute: 10)
        let now = date("2026-06-10", hour: 12, minute: 20)
        let txn = Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: "txn_1",
            amount: 12.34,
            date: "2026-06-10",
            merchantName: "Store",
            name: "Store",
            category: "Shopping",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
        XCTAssertFalse(
            TransactionSyncPolicy.shouldSyncAutomatically(
                lastClientSyncAt: lastClient,
                plaidItems: [item],
                tellerItems: [],
                transactions: [txn],
                now: now,
                calendar: calendar
            )
        )
    }

    func testShouldSyncWhenTransactionsAreStale() {
        let item = activePlaidItem(lastSyncAt: "2026-06-10T12:00:00Z")
        let lastClient = date("2026-06-10", hour: 12, minute: 5)
        let now = date("2026-06-30", hour: 9)
        let txn = Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: "txn_1",
            amount: 12.34,
            date: "2026-06-11",
            merchantName: "Store",
            name: "Store",
            category: "Shopping",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
        XCTAssertTrue(
            TransactionSyncPolicy.shouldSyncAutomatically(
                lastClientSyncAt: lastClient,
                plaidItems: [item],
                tellerItems: [],
                transactions: [txn],
                now: now,
                calendar: calendar
            )
        )
    }

    func testSyncStorePersistsPerUser() {
        let defaults = UserDefaults(suiteName: "TransactionSyncPolicyTests")!
        defaults.removePersistentDomain(forName: "TransactionSyncPolicyTests")
        let store = TransactionSyncStore(defaults: defaults)
        let syncedAt = date("2026-06-10", hour: 9)

        XCTAssertNil(store.lastSyncAt(userId: "user-a"))
        store.markSynced(userId: "user-a", at: syncedAt)
        XCTAssertEqual(store.lastSyncAt(userId: "user-a"), syncedAt)
        XCTAssertNil(store.lastSyncAt(userId: "user-b"))
    }

    private func activePlaidItem(lastSyncAt: String?) -> PlaidItem {
        PlaidItem(
            id: UUID(),
            plaidItemId: "item_1",
            institutionName: "Bank",
            status: "active",
            errorCode: nil,
            errorMessage: nil,
            lastSyncAt: lastSyncAt
        )
    }

    private func date(_ value: String, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let parts = value.split(separator: "-").map(String.init)
        components.year = Int(parts[0])
        components.month = Int(parts[1])
        components.day = Int(parts[2])
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
