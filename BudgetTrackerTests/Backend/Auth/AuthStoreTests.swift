import XCTest
import Supabase
@testable import BudgetTracker

@MainActor
final class AuthStoreTests: XCTestCase {
    func testInitDoesNotRequireSupabaseClient() {
        _ = AuthStore()
    }

    func testBootstrapWithoutConfigLeavesUnauthenticated() async {
        guard !SupabaseConfig.isConfigured else {
            throw XCTSkip("Supabase configured in test environment.")
        }
        let store = AuthStore()
        await store.bootstrap()
        XCTAssertEqual(store.state, .unauthenticated)
        XCTAssertNil(store.userId)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSupabaseClientFactoryDoesNotTrapWithValidHTTPSURL() throws {
        let url = URL(string: "https://dldbcbituquxedlkeefu.supabase.co")!
        XCTAssertEqual(SupabaseClientFactory.storageKeyHostComponent(from: url), "dldbcbituquxedlkeefu")
        _ = try SupabaseClientFactory.makeClient(
            url: url,
            anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test-signature"
        )
    }

    func testSupabaseClientFactoryRejectsUnresolvableHost() {
        let bad = URL(string: "https://")!
        XCTAssertThrowsError(try SupabaseClientFactory.makeClient(url: bad, anonKey: "key")) { error in
            XCTAssertTrue("\(error)".contains("host") || "\(error)".contains("Supabase"))
        }
    }
}
