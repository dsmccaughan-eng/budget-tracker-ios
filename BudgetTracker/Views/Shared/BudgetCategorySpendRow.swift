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
                Text(FinanceFormatting.currency(progress.spent))
                    .font(.subheadline.weight(.semibold))
                Text(remainingLabel)
                    .font(.caption)
                    .foregroundStyle(progress.remaining >= 0 ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var remainingLabel: String {
        if progress.remaining >= 0 {
            return "\(FinanceFormatting.currency(progress.remaining)) left"
        }
        return "\(FinanceFormatting.currency(abs(progress.remaining))) over"
    }
}
