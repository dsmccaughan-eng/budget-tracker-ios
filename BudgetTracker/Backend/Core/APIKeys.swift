import Foundation

struct APIKeys {
    private static let geminiUserProvidedFlag = "gemini_api_key_user_provided"
    private static let supabaseUserProvidedFlag = "supabase_keys_user_provided"

    static var gemini: String {
        resolveKey(
            envKey: "GEMINI_API_KEY",
            infoPlistKey: "GEMINI_API_KEY",
            userDefaultsKey: "gemini_api_key",
            localPlistKey: "GEMINI_API_KEY",
            userProvidedFlag: geminiUserProvidedFlag
        )
    }

    static var supabaseURL: String {
        resolveKey(
            envKey: "SUPABASE_URL",
            infoPlistKey: "SUPABASE_URL",
            userDefaultsKey: "supabase_url",
            localPlistKey: "SUPABASE_URL",
            userProvidedFlag: supabaseUserProvidedFlag
        )
    }

    static var supabaseAnonKey: String {
        resolveKey(
            envKey: "SUPABASE_ANON_KEY",
            infoPlistKey: "SUPABASE_ANON_KEY",
            userDefaultsKey: "supabase_anon_key",
            localPlistKey: "SUPABASE_ANON_KEY",
            userProvidedFlag: supabaseUserProvidedFlag
        )
    }

    static let missingGeminiKeyMessage =
        "Missing Gemini API key. Add GEMINI_API_KEY to pkg.xcconfig before archiving, or enter your key in Settings."

    static var hasValidGeminiKey: Bool { !gemini.isEmpty }
    static var hasValidSupabaseConfig: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }

    static func syncToUserDefaultsIfNeeded() {
        seedIfNeeded(
            flag: geminiUserProvidedFlag,
            defaultsKey: "gemini_api_key",
            value: geminiFromBuildSources()
        )
        seedIfNeeded(
            flag: supabaseUserProvidedFlag,
            defaultsKey: "supabase_url",
            value: supabaseURLFromBuildSources()
        )
        seedIfNeeded(
            flag: supabaseUserProvidedFlag,
            defaultsKey: "supabase_anon_key",
            value: supabaseAnonFromBuildSources()
        )
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
        userProvidedFlag: String
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

        return ""
    }

    private static func geminiFromBuildSources() -> String {
        valueFromBuildSources(envKey: "GEMINI_API_KEY", infoPlistKey: "GEMINI_API_KEY", localPlistKey: "GEMINI_API_KEY")
    }

    private static func supabaseURLFromBuildSources() -> String {
        valueFromBuildSources(envKey: "SUPABASE_URL", infoPlistKey: "SUPABASE_URL", localPlistKey: "SUPABASE_URL")
    }

    private static func supabaseAnonFromBuildSources() -> String {
        valueFromBuildSources(envKey: "SUPABASE_ANON_KEY", infoPlistKey: "SUPABASE_ANON_KEY", localPlistKey: "SUPABASE_ANON_KEY")
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

        #if DEBUG
        if let localValue = localPlistString(for: localPlistKey), isUsableKey(localValue) {
            return localValue
        }
        #endif

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

    private static func isUsableKey(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.contains("$(") { return false }
        if value.hasPrefix("YOUR_") { return false }
        return true
    }
}
