import XCTest
@testable import BudgetTracker

final class InvestmentHistoryEngineTests: XCTestCase {
    private let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
    }

    func testReconstructedDailyPointsWalksBackwardFromCurrentBalance() {
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "Brokerage",
            officialName: nil,
            type: "investment",
            subtype: "brokerage",
            mask: nil,
            currentBalance: 1_000,
            availableBalance: nil
        )

        let txns = [
            investmentTransaction(date: "2026-06-01", amount: 100),
            investmentTransaction(date: "2026-06-02", amount: -50),
        ]

        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        let points = InvestmentHistoryEngine.reconstructedDailyPoints(
            account: account,
            transactions: txns,
            referenceDate: reference,
            range: .oneMonth,
            calendar: calendar
        )

        let byDate = Dictionary(uniqueKeysWithValues: points.map { ($0.dateString, $0.balance) })
        XCTAssertEqual(byDate["2026-06-01"], 950)
        XCTAssertEqual(byDate["2026-06-02"], 1_000)
        XCTAssertEqual(byDate["2026-06-03"], 1_000)
    }

    func testChartPointsPreferSnapshotsOverReconstruction() {
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "Brokerage",
            officialName: nil,
            type: "investment",
            subtype: "brokerage",
            mask: nil,
            currentBalance: 1_200,
            availableBalance: nil
        )

        let txns = [investmentTransaction(date: "2026-06-01", amount: 100)]
        let snapshots = [
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: accountId,
                date: "2026-06-01",
                currentBalance: 1_500,
                availableBalance: nil
            ),
        ]

        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let points = InvestmentHistoryEngine.chartPoints(
            account: account,
            snapshots: snapshots,
            transactions: txns,
            range: .oneMonth,
            referenceDate: reference,
            calendar: calendar
        )

        let byDate = Dictionary(uniqueKeysWithValues: points.map { ($0.dateString, $0.balance) })
        XCTAssertEqual(byDate["2026-06-01"], 1_500)
        XCTAssertEqual(byDate["2026-06-02"], 1_200)
    }

    private func investmentTransaction(date: String, amount: Double) -> InvestmentTransaction {
        InvestmentTransaction(
            id: UUID(),
            accountId: accountId,
            securityId: nil,
            plaidInvestmentTransactionId: UUID().uuidString,
            plaidAccountId: "acc",
            plaidSecurityId: nil,
            name: "Trade",
            type: "buy",
            subtype: "buy",
            date: date,
            quantity: 1,
            amount: amount,
            price: amount,
            fees: nil,
            isoCurrencyCode: "USD"
        )
    }
}
