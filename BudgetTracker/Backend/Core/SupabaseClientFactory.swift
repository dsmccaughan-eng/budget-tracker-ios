import Foundation
import Supabase

/// Single entry point for `SupabaseClient` construction (launch-crash safeguards).
enum SupabaseClientFactory {
    /// Creates a client only when the URL host is resolvable the same way supabase-swift 2.44+ expects.
    /// Prevents calling into SDK init with hosts that would trap on iOS 26 when an old SDK is linked.
    static func makeClient(url: URL, anonKey: String) throws -> SupabaseClient {
        guard SupabaseConfig.hasResolvableHost(url) else {
            throw BudgetTrackerError.server(
                "Supabase URL host is not resolvable on this device. Check SUPABASE_URL in Settings."
            )
        }
        guard storageKeyHostComponent(from: url) != nil else {
            throw BudgetTrackerError.server(
                "Supabase URL is invalid for auth storage. Use https://<project>.supabase.co"
            )
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    /// Mirrors supabase-swift 2.44+ `host(percentEncoded:)` fallback used for the auth storage key.
    static func storageKeyHostComponent(from url: URL) -> String? {
        if #available(iOS 16.0, macOS 13.0, *) {
            if let host = url.host(percentEncoded: false), !host.isEmpty {
                return String(host.split(separator: ".")[0])
            }
        }
        if let legacy = url.host, !legacy.isEmpty {
            return String(legacy.split(separator: ".")[0])
        }
        return nil
    }
}
