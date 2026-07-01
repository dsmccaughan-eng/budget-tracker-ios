import Foundation

struct UserCategorizationHint: Equatable {
    let merchantText: String
    let category: String
    let subcategory: String?
}

enum MerchantSimilarity {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to", "us", "usa", "llc", "inc"
    ]

    private static let abbreviations: [String: String] = [
        "cr": "credit",
        "pmt": "payment",
        "pymt": "payment",
        "xfer": "transfer",
        "ach": "transfer",
        "mbl": "mobile",
        "mob": "mobile",
        "cc": "credit card"
    ]

    static func normalizeMerchantText(_ raw: String) -> String {
        var text = raw.lowercased()
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = text.split(separator: " ").map { token -> String in
            let key = String(token)
            return abbreviations[key] ?? key
        }
        return tokens.joined(separator: " ")
    }

    static func merchantTokens(_ raw: String) -> [String] {
        normalizeMerchantText(raw)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    static func similarityScore(_ left: String, _ right: String) -> Double {
        let a = normalizeMerchantText(left)
        let b = normalizeMerchantText(right)
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }

        let tokensA = merchantTokens(a)
        let tokensB = merchantTokens(b)
        if tokensA.isEmpty || tokensB.isEmpty { return 0 }

        let setA = Set(tokensA)
        let setB = Set(tokensB)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        let jaccard = union == 0 ? 0 : Double(intersection) / Double(union)

        let containsBoost = (setA.isSubset(of: setB) || setB.isSubset(of: setA)) ? 0.15 : 0
        let prefixBoost = a.hasPrefix(b) || b.hasPrefix(a) ? 0.1 : 0
        return min(1, jaccard + containsBoost + prefixBoost)
    }

    static func merchantSkeleton(_ raw: String) -> String {
        normalizeMerchantText(raw)
            .replacingOccurrences(of: #"\b\d+\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchSimilar(
        searchText: String,
        hints: [UserCategorizationHint],
        minScore: Double = 0.62
    ) -> UserCategorizationHint? {
        var best: UserCategorizationHint?
        var bestScore = minScore
        for hint in hints {
            let score = similarityScore(searchText, hint.merchantText)
            if score >= bestScore {
                best = hint
                bestScore = score
            }
            let skeletonScore = similarityScore(
                merchantSkeleton(searchText),
                merchantSkeleton(hint.merchantText)
            )
            if skeletonScore >= max(minScore, 0.58), skeletonScore >= bestScore {
                best = hint
                bestScore = skeletonScore
            }
        }
        return best
    }
}
