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

    func testReconstructedDailyPointsUsesContributionsAndIgnoresBuys() {
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "IRA",
            officialName: nil,
            type: "investment",
            subtype: "ira",
            mask: nil,
            currentBalance: 1_000,
            availableBalance: nil
        )

        let txns = [
            investmentTransaction(date: "2026-06-01", amount: -500, type: "cash", subtype: "contribution"),
            investmentTransaction(date: "2026-06-01", amount: 500, type: "buy", subtype: "buy"),
            investmentTransaction(date: "2026-06-02", amount: 200, type: "cash", subtype: "withdrawal"),
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
        XCTAssertEqual(byDate["2026-05-31"] ?? 0, 700, accuracy: 0.01)
        XCTAssertEqual(byDate["2026-06-01"] ?? 0, 1_200, accuracy: 0.01)
        XCTAssertEqual(byDate["2026-06-02"] ?? 0, 1_000, accuracy: 0.01)
        XCTAssertEqual(byDate["2026-06-03"] ?? 0, 1_000, accuracy: 0.01)
    }

    func testReconstructedDailyPointsUsesRegularAccountTransactions() {
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "401k",
            officialName: nil,
            type: "investment",
            subtype: "401k",
            mask: nil,
            currentBalance: 10_500,
            availableBalance: nil
        )
        let deposit = Transaction(
            id: UUID(),
            accountId: accountId,
            plaidTransactionId: "dep",
            amount: -500,
            date: "2026-06-01",
            merchantName: "Employer",
            name: "401k contribution",
            category: "Investments",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let points = InvestmentHistoryEngine.reconstructedDailyPoints(
            account: account,
            transactions: [],
            cashTransactions: [deposit],
            referenceDate: reference,
            range: .oneMonth,
            calendar: calendar
        )
        let byDate = Dictionary(uniqueKeysWithValues: points.map { ($0.dateString, $0.balance) })
        XCTAssertEqual(byDate["2026-05-31"] ?? 0, 10_000, accuracy: 0.01)
        XCTAssertEqual(byDate["2026-06-01"] ?? 0, 10_500, accuracy: 0.01)
        XCTAssertEqual(byDate["2026-06-02"] ?? 0, 10_500, accuracy: 0.01)
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

        let txns = [
            investmentTransaction(date: "2026-06-01", amount: -100, type: "cash", subtype: "contribution")
        ]
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

    func testAffectsTotalValueSkipsSecurityTrades() {
        XCTAssertFalse(InvestmentHistoryEngine.affectsTotalValue(type: "buy", subtype: "buy"))
        XCTAssertFalse(InvestmentHistoryEngine.affectsTotalValue(type: "sell", subtype: "sell"))
        XCTAssertFalse(InvestmentHistoryEngine.affectsTotalValue(type: "cash", subtype: "dividend reinvestment"))
        XCTAssertTrue(InvestmentHistoryEngine.affectsTotalValue(type: "cash", subtype: "contribution"))
        XCTAssertTrue(InvestmentHistoryEngine.affectsTotalValue(type: "transfer", subtype: "transfer"))
        XCTAssertTrue(InvestmentHistoryEngine.affectsTotalValue(type: "cash", subtype: "withdrawal"))
        XCTAssertTrue(InvestmentHistoryEngine.affectsTotalValue(type: "fee", subtype: "fee"))
    }

    private func investmentTransaction(
        date: String,
        amount: Double,
        type: String,
        subtype: String
    ) -> InvestmentTransaction {
        InvestmentTransaction(
            id: UUID(),
            accountId: accountId,
            securityId: nil,
            plaidInvestmentTransactionId: UUID().uuidString,
            plaidAccountId: "acc",
            plaidSecurityId: nil,
            name: subtype,
            type: type,
            subtype: subtype,
            date: date,
            quantity: 1,
            amount: amount,
            price: abs(amount),
            fees: nil,
            isoCurrencyCode: "USD"
        )
    }
}
