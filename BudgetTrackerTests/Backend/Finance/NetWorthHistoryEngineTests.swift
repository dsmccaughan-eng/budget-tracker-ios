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

    func testChartPointsPrefersSavedSnapshotOverAccountEstimate() {
        let checkingId = UUID()
        let checking = Account(
            id: checkingId,
            plaidItemId: "item",
            plaidAccountId: "chk",
            name: "Checking",
            officialName: nil,
            type: "depository",
            subtype: "checking",
            mask: "1111",
            currentBalance: 500,
            availableBalance: 500
        )
        let snaps = [snapshot(date: "2026-06-10", net: 250_000)]
        let points = NetWorthHistoryEngine.chartPoints(
            snapshots: snaps,
            accounts: [checking],
            accountSnapshots: [],
            transactions: [],
            currentAssets: 500,
            currentLiabilities: 0,
            currentNetWorth: 500,
            referenceDate: referenceDate,
            range: .oneMonth,
            calendar: calendar
        )
        let june10 = points.first { $0.dateString == "2026-06-10" }
        XCTAssertEqual(june10?.netWorth ?? 0, 250_000, accuracy: 0.01)
    }

    func testBackfillLeadingBalancesUsesFirstKnownBalance() {
        var balances = ["2026-06-10": 8_000.0]
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        NetWorthHistoryEngine.backfillLeadingBalances(
            balances: &balances,
            startDate: start,
            calendar: calendar
        )
        XCTAssertEqual(balances["2026-06-05"], 8_000)
        XCTAssertEqual(balances["2026-06-10"], 8_000)
    }

    func testSmoothIsolatedOutliersRemovesOneDayDip() {
        let points = [
            NetWorthChartPoint(
                date: referenceDate,
                dateString: "2026-06-08",
                netWorth: 500_000,
                totalAssets: 500_000,
                totalLiabilities: 0
            ),
            NetWorthChartPoint(
                date: referenceDate,
                dateString: "2026-06-09",
                netWorth: 50_000,
                totalAssets: 50_000,
                totalLiabilities: 0
            ),
            NetWorthChartPoint(
                date: referenceDate,
                dateString: "2026-06-10",
                netWorth: 510_000,
                totalAssets: 510_000,
                totalLiabilities: 0
            )
        ]
        let smoothed = NetWorthHistoryEngine.smoothIsolatedOutliers(points)
        let middle = smoothed.first { $0.dateString == "2026-06-09" }
        XCTAssertEqual(middle?.netWorth ?? 0, 505_000, accuracy: 1)
    }

    func testShouldTrustSnapshotRejectsIsolatedLowDip() {
        let previous = NetWorthChartPoint(
            date: referenceDate,
            dateString: "2026-06-08",
            netWorth: 500_000,
            totalAssets: 500_000,
            totalLiabilities: 0
        )
        let next = NetWorthChartPoint(
            date: referenceDate,
            dateString: "2026-06-10",
            netWorth: 505_000,
            totalAssets: 505_000,
            totalLiabilities: 0
        )
        let dip = NetWorthChartPoint(
            date: referenceDate,
            dateString: "2026-06-09",
            netWorth: 80_000,
            totalAssets: 80_000,
            totalLiabilities: 0
        )
        let estimate = NetWorthChartPoint(
            date: referenceDate,
            dateString: "2026-06-09",
            netWorth: 498_000,
            totalAssets: 498_000,
            totalLiabilities: 0
        )
        XCTAssertFalse(
            NetWorthHistoryEngine.shouldTrustSnapshot(
                dip,
                estimate: estimate,
                previous: previous,
                next: next
            )
        )
    }

    func testChartPointsFromAccountHistoryBackfillsInvestmentBeforeFirstSnapshot() {
        let checkingId = UUID()
        let investmentId = UUID()
        let checking = Account(
            id: checkingId,
            plaidItemId: "item",
            plaidAccountId: "chk",
            name: "Checking",
            officialName: nil,
            type: "depository",
            subtype: "checking",
            mask: "1111",
            currentBalance: 1_000,
            availableBalance: 1_000
        )
        let investment = Account(
            id: investmentId,
            plaidItemId: "item",
            plaidAccountId: "inv",
            name: "Brokerage",
            officialName: nil,
            type: "investment",
            subtype: "brokerage",
            mask: nil,
            currentBalance: 10_000,
            availableBalance: nil
        )
        let accountSnapshots = [
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: investmentId,
                date: "2026-06-01",
                currentBalance: 8_000,
                availableBalance: nil
            )
        ]
        let points = NetWorthHistoryEngine.chartPointsFromAccountHistory(
            accounts: [checking, investment],
            accountSnapshots: accountSnapshots,
            transactions: [],
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!,
            range: .oneMonth,
            calendar: calendar
        )
        let june3 = points.first { $0.dateString == "2026-06-03" }
        XCTAssertEqual(june3?.netWorth ?? 0, 10_000, accuracy: 0.01)
        let may20 = points.first { $0.dateString == "2026-05-20" }
        XCTAssertEqual(may20?.netWorth ?? 0, 9_000, accuracy: 0.01)
    }

    func testChartPointsForwardFillsSparseInvestmentSnapshots() {
        let investmentId = UUID()
        let investment = Account(
            id: investmentId,
            plaidItemId: "item",
            plaidAccountId: "inv",
            name: "Brokerage",
            officialName: nil,
            type: "investment",
            subtype: "brokerage",
            mask: nil,
            currentBalance: 12_000,
            availableBalance: nil
        )
        let accountSnapshots = [
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: investmentId,
                date: "2026-06-05",
                currentBalance: 11_000,
                availableBalance: nil
            )
        ]
        let points = NetWorthHistoryEngine.chartPointsFromAccountHistory(
            accounts: [investment],
            accountSnapshots: accountSnapshots,
            transactions: [],
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 7))!,
            range: .oneMonth,
            calendar: calendar
        )
        let june6 = points.first { $0.dateString == "2026-06-06" }
        XCTAssertEqual(june6?.netWorth ?? 0, 11_500, accuracy: 0.01)
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
        XCTAssertTrue(groups.contains { $0.kind == .debts })
        XCTAssertEqual(groups.first { $0.kind == .debts }?.total ?? 0, -200, accuracy: 0.01)
    }

    func testGroupChartPointsUsesOnlyMatchingAccounts() {
        let cashID = UUID()
        let creditID = UUID()
        let accounts = [
            Account(
                id: cashID,
                plaidItemId: "item",
                plaidAccountId: "chk",
                name: "Checking",
                officialName: nil,
                type: "depository",
                subtype: "checking",
                mask: "1111",
                currentBalance: 1_000,
                availableBalance: 1_000
            ),
            Account(
                id: creditID,
                plaidItemId: "item",
                plaidAccountId: "cc",
                name: "Visa",
                officialName: nil,
                type: "credit",
                subtype: "credit card",
                mask: "2222",
                currentBalance: 250,
                availableBalance: nil
            ),
        ]
        let cashPoints = NetWorthHistoryEngine.groupChartPoints(
            kind: .cash,
            accounts: accounts,
            referenceDate: referenceDate,
            range: .oneMonth,
            calendar: calendar
        )
        let debtPoints = NetWorthHistoryEngine.groupChartPoints(
            kind: .debts,
            accounts: accounts,
            referenceDate: referenceDate,
            range: .oneMonth,
            calendar: calendar
        )
        XCTAssertFalse(cashPoints.isEmpty)
        XCTAssertEqual(cashPoints.last?.netWorth ?? 0, 1_000, accuracy: 0.01)
        XCTAssertFalse(debtPoints.isEmpty)
        XCTAssertEqual(debtPoints.last?.netWorth ?? 0, -250, accuracy: 0.01)
    }

    func testMonthlyChartPointsUsesFirstOfMonthAndKeepsToday() {
        let daily = [
            chartPoint(date: "2026-01-01", net: 100),
            chartPoint(date: "2026-01-15", net: 110),
            chartPoint(date: "2026-02-01", net: 120),
            chartPoint(date: "2026-02-10", net: 125),
            chartPoint(date: "2026-03-01", net: 140),
            chartPoint(date: "2026-03-15", net: 150),
        ]
        let monthly = NetWorthHistoryEngine.monthlyChartPoints(from: daily, calendar: calendar)
        XCTAssertEqual(monthly.map(\.dateString), [
            "2026-01-01",
            "2026-02-01",
            "2026-03-01",
            "2026-03-15",
        ])
        XCTAssertEqual(monthly[0].netWorth, 100, accuracy: 0.01)
        XCTAssertEqual(monthly[1].netWorth, 120, accuracy: 0.01)
        XCTAssertEqual(monthly[2].netWorth, 140, accuracy: 0.01)
        XCTAssertEqual(monthly[3].netWorth, 150, accuracy: 0.01)
    }

    func testMonthlyChartPointsFallsBackToFirstDayInMonth() {
        let daily = [
            chartPoint(date: "2026-01-15", net: 100),
            chartPoint(date: "2026-02-01", net: 120),
        ]
        let monthly = NetWorthHistoryEngine.monthlyChartPoints(from: daily, calendar: calendar)
        XCTAssertEqual(monthly.map(\.dateString), ["2026-01-15", "2026-02-01"])
    }

    func testChangeFromPreviousComputesMonthOverMonth() {
        let series = [
            chartPoint(date: "2026-01-01", net: 100_000),
            chartPoint(date: "2026-02-01", net: 120_000),
        ]
        let change = NetWorthHistoryEngine.changeFromPrevious(selected: series[1], series: series)
        XCTAssertEqual(change?.amount ?? 0, 20_000, accuracy: 0.01)
        XCTAssertEqual(change?.percent ?? 0, 20, accuracy: 0.01)
    }

    private func chartPoint(date: String, net: Double) -> NetWorthChartPoint {
        let parsed = calendar.date(from: DateComponents(
            year: Int(date.prefix(4)),
            month: Int(date.dropFirst(5).prefix(2)),
            day: Int(date.suffix(2))
        ))!
        return NetWorthChartPoint(
            date: parsed,
            dateString: date,
            netWorth: net,
            totalAssets: max(net, 0),
            totalLiabilities: net < 0 ? abs(net) : 0
        )
    }
}
