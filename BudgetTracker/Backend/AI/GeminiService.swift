import Foundation

enum AIResponseNormalizer {
    static func extractJSONBlock(from response: String) -> String {
        if let fenced = response.range(of: "```", options: .backwards) {
            let inner = response[response.index(response.startIndex, offsetBy: 3)..<fenced.lowerBound]
            if let jsonStart = inner.range(of: "{") {
                return String(inner[jsonStart.lowerBound...])
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}") else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(response[start...end])
    }

    static func decode<T: Decodable>(_ type: T.Type, from response: String) throws -> T {
        let json = extractJSONBlock(from: response)
        guard let data = json.data(using: .utf8) else {
            throw GeminiServiceError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return APIKeys.missingGeminiKeyMessage
        case .invalidResponse: return "Could not parse AI response."
        case .httpError(let code): return "Gemini request failed (\(code))."
        }
    }
}

struct ReceiptParseResult: Decodable {
    let merchant: String
    let date: String
    let items: [ReceiptItem]
    let subtotal: Double?
    let tax: Double?
    let total: Double
}

struct ReceiptItem: Decodable {
    let name: String
    let quantity: Double?
    let price: Double
    let category: String?
}

struct GeminiService {
    static let shared = GeminiService()

    private let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    func parseReceipt(imageData: Data) async throws -> ReceiptParseResult {
        let system = """
        You are a receipt parser. Return ONLY valid JSON with fields: merchant (string), \
        date (yyyy-MM-dd), items (array of {name, quantity, price, category}), subtotal, tax, total.
        """
        let base64 = imageData.base64EncodedString()
        let prompt = "Parse this receipt image. Data:image/jpeg;base64,\(base64)"
        let text = try await generate(prompt: prompt, system: system)
        return try AIResponseNormalizer.decode(ReceiptParseResult.self, from: text)
    }

    private func generate(prompt: String, system: String) async throws -> String {
        let apiKey = APIKeys.gemini
        guard APIKeys.hasValidGeminiKey else { throw GeminiServiceError.missingAPIKey }

        guard var components = URLComponents(string: endpoint) else {
            throw GeminiServiceError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw GeminiServiceError.invalidResponse }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw GeminiServiceError.httpError(http.statusCode) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        guard let text = parts?.first?["text"] as? String else {
            throw GeminiServiceError.invalidResponse
        }
        return text
    }
}
