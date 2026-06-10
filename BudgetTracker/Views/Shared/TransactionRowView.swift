import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let account: Account?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(FinanceFormatting.displayName(for: transaction))
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(transaction.category)
                    if let source = CategorySource.from(transaction.categorySource) {
                        if source == .gemini {
                            Text("AI")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        } else if source == .userSimilar {
                            Text("Similar")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    if transaction.excludedFromBudget {
                        Text("Excluded")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let account {
                    Text(FinanceFormatting.accountLabel(account))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(TransactionFormatting.formattedAmount(transaction.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TransactionFormatting.amountColor(transaction.amount))
                Text(TransactionFormatting.amountLabel(transaction.amount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(transaction.date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if transaction.pending {
                    Text("Pending")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CategorySourceBadge: View {
    let source: CategorySource

    var body: some View {
        Label(source.displayLabel, systemImage: iconName)
            .font(.caption)
            .foregroundStyle(source == .gemini ? .purple : .secondary)
    }

    private var iconName: String {
        switch source {
        case .gemini: return "sparkles"
        case .merchantRule, .user: return "bookmark.fill"
        case .userSimilar: return "clock.arrow.circlepath"
        case .merchantDb: return "books.vertical.fill"
        case .plaid: return "building.columns.fill"
        case .teller: return "link"
        }
    }
}
