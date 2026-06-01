import Foundation

/// Supabase URL/key resolution for auth and cloud clients.
enum SupabaseConfig {
  static var url: URL? {
    validatedURL(from: APIKeys.supabaseURL)
  }

  static var anonKey: String { APIKeys.supabaseAnonKey }

  static var isConfigured: Bool {
    url != nil && APIKeys.hasValidSupabaseConfig
  }

  /// Minimum supabase-swift version that fixes iOS 26 `URL.host` crash in `SupabaseClient.init`.
  /// CI runs `scripts/verify-supabase-package.sh`; tests assert this constant.
  static let minimumSupabaseSwiftVersion = "2.44.0"

  /// Validates a Supabase project URL before `SupabaseClient` init (guards iOS 26 host resolution).
  static func validatedURL(from string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
    guard hasResolvableHost(url) else { return nil }
    return url
  }

  /// True when the URL has a non-empty host via modern or legacy APIs (iOS 26-safe).
  static func hasResolvableHost(_ url: URL) -> Bool {
    if #available(iOS 16.0, macOS 13.0, *) {
      if let host = url.host(percentEncoded: false), !host.isEmpty { return true }
    }
    if let legacy = url.host, !legacy.isEmpty { return true }
    return false
  }
}
