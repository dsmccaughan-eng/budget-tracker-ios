import XCTest
@testable import BudgetTracker

final class APIKeysTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "supabase_keys_user_provided")
        UserDefaults.standard.removeObject(forKey: "supabase_url")
        UserDefaults.standard.removeObject(forKey: "supabase_anon_key")
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

    func testDefaultSupabaseURLIsProductionProject() {
        XCTAssertEqual(APIKeys.defaultSupabaseURL, "https://dldbcbituquxedlkeefu.supabase.co")
    }

    func testSupabaseConfigAlwaysAvailableWithoutUserInput() {
        APIKeys.syncToUserDefaultsIfNeeded()
        XCTAssertTrue(APIKeys.hasValidSupabaseConfig)
        XCTAssertTrue(SupabaseConfig.isConfigured)
        XCTAssertEqual(APIKeys.supabaseURL, APIKeys.defaultSupabaseURL)
        XCTAssertEqual(APIKeys.supabaseAnonKey, APIKeys.defaultSupabaseAnonKey)
    }

    func testLegacyUserDefaultsOverrideIsIgnored() {
        UserDefaults.standard.set("https://example.supabase.co", forKey: "supabase_url")
        UserDefaults.standard.set("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test", forKey: "supabase_anon_key")
        UserDefaults.standard.set(true, forKey: "supabase_keys_user_provided")
        APIKeys.syncToUserDefaultsIfNeeded()
        XCTAssertEqual(APIKeys.supabaseURL, APIKeys.defaultSupabaseURL)
        XCTAssertEqual(APIKeys.supabaseAnonKey, APIKeys.defaultSupabaseAnonKey)
    }
}
