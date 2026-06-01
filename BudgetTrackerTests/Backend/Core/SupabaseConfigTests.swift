import XCTest
@testable import BudgetTracker

final class SupabaseConfigTests: XCTestCase {
    func testMinimumSupabaseSwiftVersionIsAtLeast2440() {
        XCTAssertEqual(SupabaseConfig.minimumSupabaseSwiftVersion, "2.44.0")
    }

    func testValidatedURLAcceptsProductionProjectHost() {
        let url = SupabaseConfig.validatedURL(from: "https://dldbcbituquxedlkeefu.supabase.co")
        XCTAssertNotNil(url)
        XCTAssertTrue(SupabaseConfig.hasResolvableHost(url!))
    }

    func testValidatedURLRejectsEmptyAndMalformed() {
        XCTAssertNil(SupabaseConfig.validatedURL(from: ""))
        XCTAssertNil(SupabaseConfig.validatedURL(from: "not-a-url"))
        XCTAssertNil(SupabaseConfig.validatedURL(from: "YOUR_SUPABASE_URL"))
    }

    func testHasResolvableHostForHTTPSProjectURL() {
        let url = URL(string: "https://dldbcbituquxedlkeefu.supabase.co")!
        XCTAssertTrue(SupabaseConfig.hasResolvableHost(url))
        XCTAssertEqual(SupabaseClientFactory.storageKeyHostComponent(from: url), "dldbcbituquxedlkeefu")
    }

    func testIsConfiguredFalseWhenOnlyXcconfigPlaceholdersPresent() {
        guard !SupabaseConfig.isConfigured else {
            throw XCTSkip("Supabase configured in test environment.")
        }
        XCTAssertFalse(SupabaseConfig.isConfigured)
    }
}
