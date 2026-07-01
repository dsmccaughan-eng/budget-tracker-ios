import SwiftUI

struct DashboardBudgetSummary: View {
    let spent: Double
    let budget: Double
    var onViewFullBudget: () -> Void

    private var isOverBudget: Bool {
        budget > 0 && spent > budget
    }

    private var fillFraction: Double {
        guard budget > 0 else { return 0 }
        return min(spent / budget, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This month")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(FinanceFormatting.currency(spent)) / \(FinanceFormatting.currency(budget))")
                    .font(.caption)
                    .foregroundStyle(isOverBudget ? .red : .secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(isOverBudget ? Color.red : Color.accentColor)
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 10)

            Button("View full budget", action: onViewFullBudget)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
