import Foundation

enum TransactionReviewEngine {
    static func unreviewed(
        from transactions: [Transaction],
        reviewedIDs: Set<UUID>
    ) -> [Transaction] {
        transactions
            .filter { !reviewedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
