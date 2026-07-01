import XCTest
@testable import BudgetTracker

final class HousingHeuristicsTests: XCTestCase {
    func testRentPaymentIsHousing() {
        XCTAssertTrue(
            HousingHeuristics.looksLikeHousing(merchantText: "ACH PAYMENT LANDLORD RENT 0526")
        )
    }

    func testMonthlyRentIsHousing() {
        XCTAssertTrue(
            HousingHeuristics.looksLikeHousing(merchantText: "MONTHLY RENT - GREYSTAR")
        )
    }

    func testPlaidRentCategoryIsHousing() {
        XCTAssertTrue(
            HousingHeuristics.looksLikeHousing(
                merchantText: "Online Payment",
                plaidCategory: "RENT_AND_UTILITIES",
                plaidDetailedCategory: "RENT_AND_UTILITIES_RENT"
            )
        )
    }

    func testRentalCarIsNotHousing() {
        XCTAssertFalse(
            HousingHeuristics.looksLikeHousing(merchantText: "HERTZ RENTAL CAR")
        )
    }

    func testAchRentBeatsTransferHeuristicOrder() {
        XCTAssertTrue(
            HousingHeuristics.looksLikeHousing(merchantText: "ACH DEBIT RENT PAYMENT")
        )
    }
}
