import XCTest
@testable import BudgetTracker

final class BillsEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    }

    private func txn(
        category: String,
        amount: Double,
        date: String,
        isFixedBill: Bool = false,
        billNickname: String? = nil,
        billDueDay: Int? = nil,
        billAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: amount,
            date: date,
            merchantName: "Rent Co",
            name: "Rent Co",
            category: category,
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil,
            isFixedBill: isFixedBill,
            billNickname: billNickname,
            billDueDay: billDueDay,
            billAmount: billAmount
        )
    }

    func testOnlyFixedTransactionsBecomeBills() {
        let anchorId = UUID()
        let bills = BillsEngine.bills(
            transactions: [
                txn(category: "Groceries", amount: 40, date: "2026-03-03"),
                Transaction(
                    id: anchorId,
                    accountId: UUID(),
                    plaidTransactionId: UUID().uuidString,
                    amount: 1800,
                    date: "2026-03-05",
                    merchantName: "Rent Co",
                    name: "Rent Co",
                    category: "Housing & Utilities",
                    subcategory: nil,
                    pending: false,
                    isManual: false,
                    splitItems: nil,
                    isFixedBill: true,
                    billNickname: "Apartment",
                    billDueDay: 5,
                    billAmount: 1800
                )
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills[0].transactionId, anchorId)
        XCTAssertEqual(bills[0].name, "Apartment")
    }

    func testBillMarkedPaidWhenMerchantSpendMeetsThreshold() {
        let anchorId = UUID()
        let anchor = Transaction(
            id: anchorId,
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: 100,
            date: "2026-02-05",
            merchantName: "Rent Co",
            name: "Rent Co",
            category: "Housing & Utilities",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil,
            isFixedBill: true,
            billNickname: "Rent",
            billDueDay: 5,
            billAmount: 100
        )
        let bills = BillsEngine.bills(
            transactions: [
                anchor,
                txn(category: "Housing & Utilities", amount: 90, date: "2026-03-03", isFixedBill: false)
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertTrue(bills[0].isPaid)
    }

    func testDueDayUsesOverrideThenHistoricalDay() {
        let anchor = txn(
            category: "Housing & Utilities",
            amount: 100,
            date: "2026-01-20",
            isFixedBill: true,
            billDueDay: 12
        )
        let bills = BillsEngine.bills(
            transactions: [
                anchor,
                txn(category: "Housing & Utilities", amount: 50, date: "2026-01-05"),
                txn(category: "Housing & Utilities", amount: 50, date: "2026-02-05")
            ],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(bills[0].dueDay, 12)
    }
}
