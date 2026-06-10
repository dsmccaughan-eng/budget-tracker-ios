import Foundation

@MainActor
final class TransactionReviewStore: ObservableObject {
    @Published private(set) var reviewedTransactionIDs: Set<UUID> = []

    private var activeUserId: String?

    func setActiveUser(_ userId: String?) {
        guard activeUserId != userId else { return }
        activeUserId = userId
        reviewedTransactionIDs = loadReviewedIDs(for: userId)
    }

    func unreviewed(from transactions: [Transaction]) -> [Transaction] {
        TransactionReviewEngine.unreviewed(
            from: transactions,
            reviewedIDs: reviewedTransactionIDs
        )
    }

    func markAllReviewed(transactions: [Transaction]) {
        reviewedTransactionIDs = Set(transactions.map(\.id))
        persistReviewedIDs()
    }

    private func storageKey(for userId: String?) -> String {
        "transactionReview.reviewedIDs.\(userId ?? "anonymous")"
    }

    private func loadReviewedIDs(for userId: String?) -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: storageKey(for: userId)) as? [String] else {
            return []
        }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func persistReviewedIDs() {
        let values = reviewedTransactionIDs.map(\.uuidString)
        UserDefaults.standard.set(values, forKey: storageKey(for: activeUserId))
    }
}
