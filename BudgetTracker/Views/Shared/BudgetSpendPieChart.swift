import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date

    private var usesSpendingSlices: Bool {
        BudgetMath.totalSpent(progress) > 0
    }

    private var slices: [BudgetProgress] {
        if usesSpendingSlices {
            return progress.filter { $0.spent > 0 }
        }
        return progress.filter { $0.monthlyLimit > 0 }
    }

    private var totalCenterValue: Double {
        if usesSpendingSlices {
            return BudgetMath.totalSpent(slices)
        }
        return slices.reduce(0) { $0 + $1.monthlyLimit }
    }

    private var centerTitle: String {
        usesSpendingSlices ? "Spent" : "Budgeted"
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
                        angle: .value("Amount", sliceAmount(for: row)),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: row.color))
                }
                .chartLegend(.hidden)
                .frame(height: 200)
            }

            VStack(spacing: 4) {
                Text("\(centerTitle) \(FinanceFormatting.currency(totalCenterValue))")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !usesSpendingSlices, !slices.isEmpty {
                    Text("Spending will appear when transactions sync")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func sliceAmount(for row: BudgetProgress) -> Double {
        usesSpendingSlices ? row.spent : row.monthlyLimit
    }
}
