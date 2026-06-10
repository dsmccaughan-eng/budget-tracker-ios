import XCTest
@testable import BudgetTracker

final class AccountBalanceHistoryEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
    }

    private let accountId = UUID()

    private func account(type: String = "depository", balance: Double = 1000) -> Account {
        Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "plaid",
            name: "Checking",
            officialName: nil,
            type: type,
            subtype: "checking",
            mask: "1234",
            currentBalance: balance,
            availableBalance: balance
        )
    }

    private func txn(amount: Double, date: String) -> Transaction {
        Transaction(
            id: UUID(),
            accountId: accountId,
            plaidTransactionId: UUID().uuidString,
            amount: amount,
            date: date,
            merchantName: "Store",
            name: "Store",
            category: "Shopping",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
    }

    func testBalanceAtEndOfDayUsesFutureTransactions() {
        let txns = [
            txn(amount: 50, date: "2026-06-14"),
            txn(amount: -100, date: "2026-06-10")
        ]
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!
        let balance = AccountBalanceHistoryEngine.balanceAtEndOfDay(
            day: day,
            currentBalance: 1000,
            referenceDay: referenceDate,
            transactions: txns,
            calendar: calendar
        )
        XCTAssertEqual(balance, 1050, accuracy: 0.01)
    }

    func testCreditAccountDisplaysNegativeBalance() {
        let value = AccountBalanceHistoryEngine.displayBalance(500, accountType: "credit")
        XCTAssertEqual(value, -500, accuracy: 0.01)
    }

    func testHistoryPrefersSnapshotOverReconstructed() {
        let account = account(balance: 1000)
        let snapshots = [
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: accountId,
                date: "2026-06-10",
                currentBalance: 888,
                availableBalance: 888
            )
        ]
        let points = AccountBalanceHistoryEngine.historyPoints(
            account: account,
            snapshots: snapshots,
            transactions: [txn(amount: 50, date: "2026-06-14")],
            referenceDate: referenceDate,
            range: .oneMonth,
            calendar: calendar
        )
        let snapPoint = points.first { $0.dateString == "2026-06-10" }
        XCTAssertEqual(snapPoint?.balance ?? 0, 888, accuracy: 0.01)
        XCTAssertEqual(snapPoint?.source, .snapshot)
    }
}
