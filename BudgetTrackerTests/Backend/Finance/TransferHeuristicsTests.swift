import XCTest
@testable import BudgetTracker

final class TransferHeuristicsTests: XCTestCase {
    func testMobileCreditCardIsTransfer() {
        XCTAssertTrue(
            TransferHeuristics.looksLikeTransfer(merchantText: "MOBILE CREDIT CARD TRANSFER")
        )
    }

    func testMobilGasDoesNotMatchMobileCreditCardHeuristic() {
        XCTAssertFalse(
            TransferHeuristics.looksLikeTransfer(merchantText: "MOBIL GAS STATION #123")
        )
    }

    func testCreditCardPaymentIsTransfer() {
        XCTAssertTrue(
            TransferHeuristics.looksLikeTransfer(merchantText: "Online Credit Card Payment")
        )
    }

    func testPlaidLoanPaymentHintsTransfer() {
        XCTAssertTrue(
            TransferHeuristics.looksLikeTransfer(
                merchantText: "Payment",
                plaidCategory: "LOAN_PAYMENTS"
            )
        )
    }
}
