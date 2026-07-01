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

    func testMobilePmtWithoutCreditCardIsTransfer() {
        XCTAssertTrue(
            TransferHeuristics.looksLikeTransfer(merchantText: "ONLINE MOBILE PMT 482910")
        )
    }

    func testMetroCreditUnionMobilePaymentIsTransfer() {
        let merchants = [
            (pattern: "metro", category: "Transport", subcategory: Optional<String>.none),
        ]
        let match = CategorizationEngine.matchMerchantDB(
            merchantText: "METRO CREDIT UNION MOBILE PMT",
            merchants: merchants
        )
        XCTAssertEqual(match?.category, "Transfers")
    }

    func testRentPaymentIsHousingNotTransfer() {
        let match = CategorizationEngine.matchMerchantDB(
            merchantText: "ACH PAYMENT RENT GREYSTAR",
            merchants: [
                (pattern: "ach payment", category: "Transfers", subcategory: Optional<String>.none),
            ]
        )
        XCTAssertEqual(match?.category, "Housing & Utilities")
    }

    func testTMobileBillIsNotCreditCardTransfer() {
        XCTAssertFalse(
            TransferHeuristics.looksLikeTransfer(merchantText: "T-MOBILE POSTPAID PMT")
        )
    }
}
