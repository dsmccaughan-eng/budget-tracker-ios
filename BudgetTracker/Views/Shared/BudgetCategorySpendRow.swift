import SwiftUI

struct BudgetCategorySpendRow: View {
    let progress: BudgetProgress
    let recentSummary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: progress.color))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.category)
                    .font(.subheadline.weight(.semibold))
                if !recentSummary.isEmpty {
                    Text(recentSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(amountColor)
                if progress.showsBudgetLimit {
                    if progress.projectedSpend > 0 {
                        Text("Typical \(FinanceFormatting.currency(progress.projectedSpend))")
                            .font(.caption2)
                            .foregroundStyle(
                                progress.projectedSpend > progress.monthlyLimit ? Color.orange : Color.secondary
                            )
                    }
                    Text(remainingLabel)
                        .font(.caption)
                        .foregroundStyle(progress.remaining >= 0 ? Color.secondary : Color.red)
                } else {
                    Text(informationalSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var amountLabel: String {
        let value = progress.listDisplaySpent
        switch progress.category {
        case "Income":
            return "+\(FinanceFormatting.currency(value))"
        default:
            return FinanceFormatting.currency(value)
        }
    }

    private var amountColor: Color {
        progress.category == "Income" ? .green : .primary
    }

    private var informationalSubtitle: String {
        switch progress.category {
        case "Income":
            return "Received this month"
        case "Transfers":
            return "Not in budget chart"
        default:
            return "No budget set"
        }
    }

    private var remainingLabel: String {
        if progress.remaining >= 0 {
            return "\(FinanceFormatting.currency(progress.remaining)) left"
        }
        return "\(FinanceFormatting.currency(abs(progress.remaining))) over"
    }
}
