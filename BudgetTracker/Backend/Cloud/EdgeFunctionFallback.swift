import Foundation

enum EdgeFunctionFallback {
    /// True when the Edge Function URL is missing (not deployed) or otherwise unavailable.
    static func isMissingFunction(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        if message.contains("404") { return true }
        if message.contains("not found") { return true }
        if message.contains("non-2xx") && message.contains("404") { return true }
        return false
    }
}
