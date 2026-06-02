import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true

    private var usesSpendingSlices: Bool {
        BudgetMath.totalSpent(progress) > 0
    }

    private var slices: [BudgetProgress] {
        if usesSpendingSlices {
            return progress.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }
        }
        return progress.filter { $0.monthlyLimit > 0 }.sorted { $0.monthlyLimit > $1.monthlyLimit }
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

    private var typicalMonthly: Double {
        progress.reduce(0) { $0 + $1.projectedSpend }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5).opacity(0.6), lineWidth: 14)
                .frame(width: 196, height: 196)

            if slices.isEmpty {
                Circle()
                    .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 14, dash: [6, 4]))
                    .frame(width: 196, height: 196)
            } else {
                Chart(slices) { row in
                    SectorMark(
                        angle: .value("Amount", sliceAmount(for: row)),
                        innerRadius: .ratio(0.64),
                        angularInset: 2.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(Color(hex: row.color))
                    .opacity(usesSpendingSlices ? 1 : 0.88)
                }
                .chartLegend(.hidden)
                .frame(width: 196, height: 196)
            }

            VStack(spacing: 3) {
                Text(centerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(FinanceFormatting.currency(totalCenterValue))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !usesSpendingSlices, typicalMonthly > 0 {
                    Text("Typical \(FinanceFormatting.currency(typicalMonthly))/mo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                } else if !usesSpendingSlices, !hasTransactions {
                    Text("Sync transactions to track spending")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                } else if !usesSpendingSlices, hasTransactions {
                    Text("No spending this month yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func sliceAmount(for row: BudgetProgress) -> Double {
        usesSpendingSlices ? row.spent : row.monthlyLimit
    }
}
