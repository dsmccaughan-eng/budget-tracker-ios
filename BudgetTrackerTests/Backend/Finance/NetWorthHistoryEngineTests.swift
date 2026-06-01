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
        XCTAssertEqual(points.first?.netWorth, 100_000, accuracy: 0.01)
        XCTAssertEqual(points.last?.netWorth, 500_000, accuracy: 0.01)
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
        XCTAssertEqual(change?.amount, 50_000, accuracy: 0.01)
        XCTAssertEqual(change?.percent, 50, accuracy: 0.01)
    }
}
