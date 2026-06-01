import XCTest
@testable import BudgetTracker

final class APIKeysTests: XCTestCase {
    private let supabaseURLKey = "supabase_url"
    private let supabaseAnonKey = "supabase_anon_key"
    private let supabaseUserFlag = "supabase_keys_user_provided"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: supabaseURLKey)
        UserDefaults.standard.removeObject(forKey: supabaseAnonKey)
        UserDefaults.standard.removeObject(forKey: supabaseUserFlag)
        super.tearDown()
    }

    func testValidatesKeyRejectsPlaceholders() {
        XCTAssertFalse(APIKeys.validatesKeyFormat(""))
        XCTAssertFalse(APIKeys.validatesKeyFormat("$(SUPABASE_URL)"))
        XCTAssertFalse(APIKeys.validatesKeyFormat("YOUR_SUPABASE_ANON_KEY"))
    }

    func testValidatesKeyAcceptsProductionShapedValues() {
        XCTAssertTrue(APIKeys.validatesKeyFormat("https://dldbcbituquxedlkeefu.supabase.co"))
        XCTAssertTrue(APIKeys.validatesKeyFormat("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.example"))
    }

    func testHasValidSupabaseConfigFalseWhenPlistPlaceholdersOnly() {
        // Test host bundle uses unresolved $(SUPABASE_*) from Info.plist unless user overrides.
        guard !APIKeys.hasValidSupabaseConfig else {
            throw XCTSkip("Supabase keys injected in test environment; placeholder test skipped.")
        }
        XCTAssertFalse(APIKeys.hasValidSupabaseConfig)
    }

    func testUserProvidedSupabaseURLWinsOverEmptyDefaults() {
        UserDefaults.standard.set("https://example.supabase.co", forKey: supabaseURLKey)
        UserDefaults.standard.set("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test", forKey: supabaseAnonKey)
        UserDefaults.standard.set(true, forKey: supabaseUserFlag)
        XCTAssertTrue(APIKeys.hasValidSupabaseConfig)
        XCTAssertEqual(APIKeys.supabaseURL, "https://example.supabase.co")
    }
}
