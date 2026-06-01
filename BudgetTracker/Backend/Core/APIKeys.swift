import Foundation

struct APIKeys {
    /// Public project URL (safe to ship in the client).
    static let defaultSupabaseURL = "https://dldbcbituquxedlkeefu.supabase.co"
    /// Anon public key (safe in client; protected by RLS). Shipped in app — never prompt the user.
    static let defaultSupabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRsZGJjYml0dXF1eGVkbGtlZWZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2OTgxNDYsImV4cCI6MjA5NTI3NDE0Nn0.ZEKbCfVCOPd_tII-7dokUNDllqi1PGTLMxH5GCOV0d0"

    private static let geminiUserProvidedFlag = "gemini_api_key_user_provided"

    static var gemini: String {
        resolveKey(
            envKey: "GEMINI_API_KEY",
            infoPlistKey: "GEMINI_API_KEY",
            userDefaultsKey: "gemini_api_key",
            localPlistKey: "GEMINI_API_KEY",
            userProvidedFlag: geminiUserProvidedFlag,
            compiledDefault: ""
        )
    }

    static var supabaseURL: String {
        resolveSupabaseValue(
            envKey: "SUPABASE_URL",
            infoPlistKey: "SUPABASE_URL",
            localPlistKey: "SUPABASE_URL",
            defaultValue: defaultSupabaseURL
        )
    }

    static var supabaseAnonKey: String {
        resolveSupabaseValue(
            envKey: "SUPABASE_ANON_KEY",
            infoPlistKey: "SUPABASE_ANON_KEY",
            localPlistKey: "SUPABASE_ANON_KEY",
            defaultValue: defaultSupabaseAnonKey
        )
    }

    static let missingGeminiKeyMessage =
        "Missing Gemini API key. Add GEMINI_API_KEY to pkg.xcconfig before archiving."

    static var hasValidGeminiKey: Bool { !gemini.isEmpty }
    static var hasValidSupabaseConfig: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }

    /// Supabase keys are baked in — do not use in-app overrides.
    @available(*, deprecated, message: "Supabase keys are configured in the app binary.")
    static func saveUserSupabaseKeys(url: String, anonKey: String) {
        _ = (url, anonKey)
    }

    static func syncToUserDefaultsIfNeeded() {
        clearLegacySupabaseUserDefaults()
        seedIfNeeded(
            flag: geminiUserProvidedFlag,
            defaultsKey: "gemini_api_key",
            value: geminiFromBuildSources()
        )
    }

    private static func clearLegacySupabaseUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "supabase_keys_user_provided")
        UserDefaults.standard.removeObject(forKey: "supabase_url")
        UserDefaults.standard.removeObject(forKey: "supabase_anon_key")
    }

    private static func resolveSupabaseValue(
        envKey: String,
        infoPlistKey: String,
        localPlistKey: String,
        defaultValue: String
    ) -> String {
        let fromBuild = valueFromBuildSources(
            envKey: envKey,
            infoPlistKey: infoPlistKey,
            localPlistKey: localPlistKey
        )
        if isUsableKey(fromBuild) { return fromBuild }
        return defaultValue
    }

    private static func seedIfNeeded(flag: String, defaultsKey: String, value: String) {
        guard !UserDefaults.standard.bool(forKey: flag),
              UserDefaults.standard.string(forKey: defaultsKey)?.isEmpty != false,
              isUsableKey(value) else { return }
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    private static func resolveKey(
        envKey: String,
        infoPlistKey: String,
        userDefaultsKey: String,
        localPlistKey: String,
        userProvidedFlag: String,
        compiledDefault: String
    ) -> String {
        if UserDefaults.standard.bool(forKey: userProvidedFlag),
           let defaultsValue = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let trimmed = defaultsValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableKey(trimmed) { return trimmed }
        }

        let fromBuild = valueFromBuildSources(
            envKey: envKey,
            infoPlistKey: infoPlistKey,
            localPlistKey: localPlistKey
        )
        if isUsableKey(fromBuild) { return fromBuild }

        if let defaultsValue = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let trimmed = defaultsValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableKey(trimmed) { return trimmed }
        }

        if isUsableKey(compiledDefault) { return compiledDefault }
        return ""
    }

    private static func geminiFromBuildSources() -> String {
        valueFromBuildSources(envKey: "GEMINI_API_KEY", infoPlistKey: "GEMINI_API_KEY", localPlistKey: "GEMINI_API_KEY")
    }

    private static func valueFromBuildSources(
        envKey: String,
        infoPlistKey: String,
        localPlistKey: String
    ) -> String {
        let envValue = ProcessInfo.processInfo.environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isUsableKey(envValue) { return envValue }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
            let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableKey(trimmed) { return trimmed }
        }

        if let localValue = localPlistString(for: localPlistKey), isUsableKey(localValue) {
            return localValue
        }

        return ""
    }

    private static func localPlistString(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "LocalAPIKeys", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shared with tests (`APIKeysTests`) — rejects xcconfig placeholders and empty strings.
    static func validatesKeyFormat(_ value: String) -> Bool {
        isUsableKey(value)
    }

    private static func isUsableKey(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.contains("$(") { return false }
        if value.hasPrefix("YOUR_") { return false }
        return true
    }
}
