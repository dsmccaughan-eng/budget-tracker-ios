import XCTest
@testable import BudgetTracker

final class TransactionReviewEngineTests: XCTestCase {
    func testUnreviewedExcludesReviewedIDs() {
        let reviewed = UUID()
        let fresh = UUID()
        let transactions = [
            makeTransaction(id: reviewed, date: "2026-06-01"),
            makeTransaction(id: fresh, date: "2026-06-02")
        ]

        let result = TransactionReviewEngine.unreviewed(
            from: transactions,
            reviewedIDs: [reviewed]
        )

        XCTAssertEqual(result.map(\.id), [fresh])
    }

    func testUnreviewedSortsNewestDateFirst() {
        let older = UUID()
        let newer = UUID()
        let transactions = [
            makeTransaction(id: older, date: "2026-05-01"),
            makeTransaction(id: newer, date: "2026-06-01")
        ]

        let result = TransactionReviewEngine.unreviewed(
            from: transactions,
            reviewedIDs: []
        )

        XCTAssertEqual(result.map(\.id), [newer, older])
    }

    private func makeTransaction(id: UUID, date: String) -> Transaction {
        Transaction(
            id: id,
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: -12.34,
            date: date,
            merchantName: "Coffee Shop",
            name: "Coffee Shop",
            category: "Food & Drink",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil
        )
    }
}
