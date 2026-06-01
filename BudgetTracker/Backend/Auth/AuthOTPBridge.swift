import Foundation

/// Fallback when Supabase email delivery fails — calls `request-login-otp` edge function.
enum AuthOTPBridge {
    struct EdgeOTPResponse: Decodable {
        let ok: Bool?
        let otp: String?
        let delivery: String?
        let error: String?
    }

    static func requestInAppOTP(email: String) async throws -> String? {
        guard SupabaseConfig.isConfigured,
              let base = SupabaseConfig.url else { return nil }

        let endpoint = base.appendingPathComponent("functions/v1/request-login-otp")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 403 { return nil }

        if http.statusCode >= 400 {
            if let decoded = try? JSONDecoder().decode(EdgeOTPResponse.self, from: data),
               let message = decoded.error, !message.isEmpty {
                throw BudgetTrackerError.server(message)
            }
            throw BudgetTrackerError.server("Could not request sign-in code.")
        }

        let decoded = try JSONDecoder().decode(EdgeOTPResponse.self, from: data)
        if decoded.delivery == "in_app", let otp = decoded.otp, !otp.isEmpty {
            return otp
        }
        return nil
    }
}
