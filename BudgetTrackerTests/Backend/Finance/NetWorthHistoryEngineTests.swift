import XCTest
@testable import BudgetTracker

final class NetWorthHistoryEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
    }

    private func snapshot(date: String, net: Double) -> NetWorthSnapshot {
        NetWorthSnapshot(
            id: UUID(),
            date: date,
            totalAssets: net + 100,
            totalLiabilities: 100,
            netWorth: net
        )
    }

    func testChartPointsIncludesTodayAndSnapshotsSorted() {
        let snaps = [
            snapshot(date: "2026-04-01", net: 100_000),
            snapshot(date: "2026-05-01", net: 110_000)
        ]
        let points = NetWorthHistoryEngine.chartPoints(
            snapshots: snaps,
            currentAssets: 520_000,
            currentLiabilities: 20_000,
            currentNetWorth: 500_000,
            referenceDate: referenceDate,
            range: .all,
            calendar: calendar
        )
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.first?.netWorth ?? 0, 100_000, accuracy: 0.01)
        XCTAssertEqual(points.last?.netWorth ?? 0, 500_000, accuracy: 0.01)
        XCTAssertEqual(points.last?.dateString, "2026-06-15")
    }

    func testChartPointsFiltersByRange() {
        let snaps = [
            snapshot(date: "2024-01-01", net: 50_000),
            snapshot(date: "2026-05-01", net: 110_000)
        ]
        let points = NetWorthHistoryEngine.chartPoints(
            snapshots: snaps,
            currentAssets: 120_000,
            currentLiabilities: 10_000,
            currentNetWorth: 110_000,
            referenceDate: referenceDate,
            range: .oneYear,
            calendar: calendar
        )
        XCTAssertFalse(points.contains { $0.dateString == "2024-01-01" })
        XCTAssertTrue(points.contains { $0.dateString == "2026-05-01" })
    }

    func testChangeFromStartComputesPercent() {
        let series = [
            NetWorthChartPoint(
                date: referenceDate,
                dateString: "2026-01-01",
                netWorth: 100_000,
                totalAssets: 100_000,
                totalLiabilities: 0
            ),
            NetWorthChartPoint(
                date: referenceDate,
                dateString: "2026-06-15",
                netWorth: 150_000,
                totalAssets: 150_000,
                totalLiabilities: 0
            )
        ]
        let change = NetWorthHistoryEngine.changeFromStart(selected: series[1], series: series)
        XCTAssertEqual(change?.amount ?? 0, 50_000, accuracy: 0.01)
        XCTAssertEqual(change?.percent ?? 0, 50, accuracy: 0.01)
    }

    func testChartPointsFromAccountHistoryBuildsDailySeries() {
        let accountId = UUID()
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "plaid",
            name: "Checking",
            officialName: nil,
            type: "depository",
            subtype: "checking",
            mask: "1234",
            currentBalance: 1000,
            availableBalance: 1000
        )
        let txns = [
            Transaction(
                id: UUID(),
                accountId: accountId,
                plaidTransactionId: UUID().uuidString,
                amount: 50,
                date: "2026-06-14",
                merchantName: "Store",
                name: "Store",
                category: "Shopping",
                subcategory: nil,
                pending: false,
                isManual: false,
                splitItems: nil
            )
        ]
        let points = NetWorthHistoryEngine.chartPointsFromAccountHistory(
            accounts: [account],
            accountSnapshots: [],
            transactions: txns,
            referenceDate: referenceDate,
            range: .oneMonth,
            calendar: calendar
        )
        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.last?.netWorth ?? 0, 1000, accuracy: 0.01)
    }

    func testAccountGroupsBucketsByType() {
        let accounts = [
            Account(
                id: UUID(),
                plaidItemId: "item",
                plaidAccountId: "chk",
                name: "Checking",
                officialName: nil,
                type: "depository",
                subtype: "checking",
                mask: "1111",
                currentBalance: 500,
                availableBalance: 500
            ),
            Account(
                id: UUID(),
                plaidItemId: "item",
                plaidAccountId: "cc",
                name: "Visa",
                officialName: nil,
                type: "credit",
                subtype: "credit card",
                mask: "2222",
                currentBalance: 200,
                availableBalance: nil
            )
        ]
        let groups = NetWorthHistoryEngine.accountGroups(from: accounts)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.title, "Cash")
        XCTAssertTrue(groups.contains { $0.title == "Loan" })
    }
}
