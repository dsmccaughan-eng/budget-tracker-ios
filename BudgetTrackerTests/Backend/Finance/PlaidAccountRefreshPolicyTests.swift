import XCTest
@testable import BudgetTracker

final class PlaidAccountRefreshPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testHasRefreshablePlaidItemsIgnoresRevokedOnly() {
        let revoked = PlaidItem(
            id: UUID(),
            plaidItemId: "item_1",
            institutionName: "Bank",
            status: "revoked",
            errorCode: nil,
            errorMessage: nil,
            lastSyncAt: nil
        )
        XCTAssertFalse(PlaidAccountRefreshPolicy.hasRefreshablePlaidItems([revoked]))
    }

    func testHasRefreshablePlaidItemsIncludesActive() {
        let active = PlaidItem(
            id: UUID(),
            plaidItemId: "item_1",
            institutionName: "Bank",
            status: "active",
            errorCode: nil,
            errorMessage: nil,
            lastSyncAt: nil
        )
        XCTAssertTrue(PlaidAccountRefreshPolicy.hasRefreshablePlaidItems([active]))
    }

    func testShouldRefreshAutomaticallyWhenNeverRefreshed() {
        let now = date("2026-06-10")
        XCTAssertTrue(
            PlaidAccountRefreshPolicy.shouldRefreshAutomatically(
                lastRefreshAt: nil,
                now: now,
                calendar: calendar
            )
        )
    }

    func testShouldRefreshAutomaticallyOnNewDay() {
        let last = date("2026-06-09", hour: 23)
        let now = date("2026-06-10", hour: 1)
        XCTAssertTrue(
            PlaidAccountRefreshPolicy.shouldRefreshAutomatically(
                lastRefreshAt: last,
                now: now,
                calendar: calendar
            )
        )
    }

    func testShouldNotRefreshAutomaticallySameDay() {
        let last = date("2026-06-10", hour: 8)
        let now = date("2026-06-10", hour: 20)
        XCTAssertFalse(
            PlaidAccountRefreshPolicy.shouldRefreshAutomatically(
                lastRefreshAt: last,
                now: now,
                calendar: calendar
            )
        )
    }

    func testRefreshStorePersistsLastRefreshPerUser() {
        let defaults = UserDefaults(suiteName: "PlaidAccountRefreshPolicyTests")!
        defaults.removePersistentDomain(forName: "PlaidAccountRefreshPolicyTests")
        let store = PlaidAccountRefreshStore(defaults: defaults)
        let refreshedAt = date("2026-06-10", hour: 9)

        XCTAssertNil(store.lastRefreshAt(userId: "user-a"))
        store.markRefreshed(userId: "user-a", at: refreshedAt)
        XCTAssertEqual(store.lastRefreshAt(userId: "user-a"), refreshedAt)
        XCTAssertNil(store.lastRefreshAt(userId: "user-b"))
    }

    private func date(_ value: String, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let parts = value.split(separator: "-").map(String.init)
        components.year = Int(parts[0])
        components.month = Int(parts[1])
        components.day = Int(parts[2])
        components.hour = hour
        return calendar.date(from: components)!
    }
}
