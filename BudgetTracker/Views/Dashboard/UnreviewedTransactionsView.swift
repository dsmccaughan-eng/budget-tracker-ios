import SwiftUI

struct UnreviewedTransactionsView: View {
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var transactionReview: TransactionReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
    @State private var scrollAnchorTransactionID: UUID?
    @State private var showReviewConfirmed = false

    private var unreviewed: [Transaction] {
        transactionReview.unreviewed(from: transactions.transactions)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    if unreviewed.isEmpty {
                        ContentUnavailableView(
                            "You're caught up",
                            systemImage: "checkmark.circle",
                            description: Text("New synced transactions will appear here for review.")
                        )
                    } else {
                        Section {
                            ForEach(unreviewed) { transaction in
                                NavigationLink(value: transaction.id) {
                                    reviewRow(transaction)
                                }
                                .id(transaction.id)
                            }
                        } footer: {
                            Text("Change a category, then return here to keep going. Your place in the list is kept.")
                        }

                        Section {
                            Button("Confirm all categorized") {
                                transactionReview.markAllReviewed(transactions: transactions.transactions)
                                showReviewConfirmed = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: UUID.self) { transactionID in
                    reviewDestination(transactionID)
                }
                .onChange(of: path.count) { oldCount, newCount in
                    guard newCount == 0, oldCount > 0,
                          let anchorID = scrollAnchorTransactionID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(anchorID, anchor: .center)
                        }
                    }
                }
                .alert("Review complete", isPresented: $showReviewConfirmed) {
                    Button("OK") { dismiss() }
                } message: {
                    Text("New transactions will appear here after your next sync.")
                }
            }
        }
    }

    @ViewBuilder
    private func reviewDestination(_ transactionID: UUID) -> some View {
        if let transaction = transactions.transactions.first(where: { $0.id == transactionID }) {
            TransactionDetailView(
                transaction: transaction,
                dismissOnCategorySave: true
            )
            .onAppear { scrollAnchorTransactionID = transactionID }
        } else {
            ContentUnavailableView(
                "Transaction unavailable",
                systemImage: "creditcard",
                description: Text("This transaction is no longer in your list.")
            )
        }
    }

    private func reviewRow(_ transaction: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(FinanceFormatting.displayName(for: transaction))
                Text(transaction.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TransactionFormatting.formattedAmount(transaction.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TransactionFormatting.amountColor(transaction.amount))
        }
    }
}
