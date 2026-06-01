import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date

    private var slices: [BudgetProgress] {
        progress.filter { $0.spent > 0 }
    }

    private var totalSpent: Double {
        BudgetMath.totalSpent(slices)
    }

    var body: some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                    .frame(width: 180, height: 180)
            } else {
                Chart(slices) { row in
                    SectorMark(
                        angle: .value("Spent", row.spent),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: row.color))
                }
                .chartLegend(.hidden)
                .frame(height: 200)
            }

            VStack(spacing: 4) {
                Text("Spent \(FinanceFormatting.currency(totalSpent))")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
