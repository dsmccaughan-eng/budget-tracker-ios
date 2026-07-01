import Foundation

/// Rent and housing payments before transfer heuristics (ACH rent is often tagged LOAN_PAYMENTS).
enum HousingHeuristics {
    private static let substringPatterns = [
        "rent payment",
        "monthly rent",
        "apt rent",
        "apartment rent",
        "landlord",
        "property management",
        "property mgmt",
        "lease payment",
        "rental payment",
        "housing payment",
        "home rent",
        "residential rent",
        "pay rent",
        "appfolio",
        "greystar",
        "equity residential",
        "avalon communities",
        "camden living",
        "progress residential",
        "invitation homes",
        "american homes 4 rent",
        "firstkey homes",
        "morgan properties",
        "lincoln property",
    ]

    private static let exclusions = [
        "rental car",
        "rent the runway",
        "tool rental",
        "equipment rental",
    ]

    static func looksLikeHousing(
        merchantText: String,
        plaidCategory: String? = nil,
        plaidDetailedCategory: String? = nil
    ) -> Bool {
        let lower = merchantText.lowercased()
        if exclusions.contains(where: { lower.contains($0) }) { return false }

        let normalized = MerchantSimilarity.normalizeMerchantText(merchantText)
        if normalized.range(of: #"\brent\b"#, options: .regularExpression) != nil {
            return true
        }
        if substringPatterns.contains(where: { normalized.contains($0) }) {
            return true
        }

        for raw in [plaidDetailedCategory, plaidCategory].compactMap({ $0 }) {
            let key = raw.uppercased().replacingOccurrences(of: " ", with: "_")
            if key.contains("RENT_AND_UTILITIES") || key.contains("_RENT") || key == "RENT" {
                return true
            }
        }
        return false
    }
}
