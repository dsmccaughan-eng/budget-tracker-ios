import XCTest
@testable import BudgetTracker

final class MerchantSimilarityTests: XCTestCase {
    func testMobileCreditCardVariantsScoreHighly() {
        let score = MerchantSimilarity.similarityScore(
            "MOBILE CREDIT CARD TRANSFER",
            "MOBILE CR CARD PMT"
        )
        XCTAssertGreaterThanOrEqual(score, 0.62)
    }

    func testMobilGasDoesNotMatchMobileCreditCard() {
        let score = MerchantSimilarity.similarityScore(
            "MOBILE CREDIT CARD PAYMENT",
            "MOBIL GAS STATION"
        )
        XCTAssertLessThan(score, 0.62)
    }

    func testMatchSimilarUsesPastHint() {
        let hints = [
            UserCategorizationHint(
                merchantText: "MOBILE CREDIT CARD PAYMENT",
                category: "Transfers",
                subcategory: nil
            )
        ]
        let match = MerchantSimilarity.matchSimilar(
            searchText: "MOBILE CR CARD TRANSFER",
            hints: hints
        )
        XCTAssertEqual(match?.category, "Transfers")
    }
}
