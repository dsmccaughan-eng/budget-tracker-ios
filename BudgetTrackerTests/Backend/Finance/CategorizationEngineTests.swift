import XCTest
@testable import BudgetTracker

final class CategorizationEngineTests: XCTestCase {
    func testMerchantRuleMatchIsCaseInsensitive() {
        let rules = [(contains: "STARBUCKS", category: "Dining & Bars", subcategory: Optional<String>.none)]
        let match = CategorizationEngine.matchMerchantRules(
            merchantText: "Purchase at Starbucks #123",
            rules: rules
        )
        XCTAssertEqual(match?.category, "Dining & Bars")
    }

    func testMerchantDBMatchFindsSubstring() {
        let merchants = [(pattern: "amazon", category: "Shopping", subcategory: Optional<String>.none)]
        let nonMatch = CategorizationEngine.matchMerchantDB(
            merchantText: "AMZN MKTP US",
            merchants: merchants
        )
        XCTAssertNil(nonMatch)

        let amazonMatch = CategorizationEngine.matchMerchantDB(
            merchantText: "Amazon.com",
            merchants: merchants
        )
        XCTAssertEqual(amazonMatch?.category, "Shopping")
    }

    func testMerchantDBDoesNotMatchMobilInsideMobileCreditCard() {
        let merchants = [
            (pattern: "mobil", category: "Transport", subcategory: Optional<String>.none),
            (pattern: "mobile credit card", category: "Transfers", subcategory: Optional<String>.none)
        ]
        let match = CategorizationEngine.matchMerchantDB(
            merchantText: "MOBILE CREDIT CARD PAYMENT",
            merchants: merchants
        )
        XCTAssertEqual(match?.category, "Transfers")
    }

    func testMobilGasMatchesWithWordBoundary() {
        let merchants = [(pattern: "mobil", category: "Transport", subcategory: Optional<String>.none)]
        let match = CategorizationEngine.matchMerchantDB(
            merchantText: "Mobil Gas",
            merchants: merchants
        )
        XCTAssertEqual(match?.category, "Transport")
    }

    func testInvalidCategoryIsIgnored() {
        let rules = [(contains: "foo", category: "Not A Category", subcategory: Optional<String>.none)]
        let match = CategorizationEngine.matchMerchantRules(
            merchantText: "foo bar",
            rules: rules
        )
        XCTAssertNil(match)
    }

    func testBudgetCategoriesContainsLockedSet() {
        XCTAssertTrue(BudgetCategories.all.contains("Groceries"))
        XCTAssertTrue(BudgetCategories.all.contains("Transfers"))
        XCTAssertEqual(BudgetCategories.all.count, 19)
        XCTAssertTrue(BudgetCategories.all.contains("Insurance"))
        XCTAssertTrue(BudgetCategories.all.contains("Investments"))
    }
}
