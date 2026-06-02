import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true

    @State private var selectedAmount: Double?
    @State private var selectedCategory: String?

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

    private var selectedRow: BudgetProgress? {
        guard let selectedCategory else { return nil }
        return slices.first { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 8) {
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
                            angularInset: selectedCategory == row.category ? 4 : 2.5
                        )
                        .cornerRadius(5)
                        .foregroundStyle(Color(hex: row.color))
                        .opacity(fadedOpacity(for: row))
                    }
                    .chartAngleSelection(value: $selectedAmount)
                    .chartLegend(.hidden)
                    .frame(width: 196, height: 196)
                }

                centerLabels
                    .padding(.horizontal, 36)
            }

            if selectedRow != nil {
                Text("Tap again to clear")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onChange(of: selectedAmount) { _, newValue in
            guard let newValue else {
                selectedCategory = nil
                return
            }
            selectedCategory = category(matchingAmount: newValue)
        }
    }

    @ViewBuilder
    private var centerLabels: some View {
        if let row = selectedRow {
            VStack(spacing: 3) {
                Text(row.category)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(FinanceFormatting.currency(sliceAmount(for: row)))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
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
                } else if usesSpendingSlices, !slices.isEmpty {
                    Text("Tap a slice for details")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func fadedOpacity(for row: BudgetProgress) -> Double {
        guard selectedCategory != nil else { return usesSpendingSlices ? 1 : 0.88 }
        return selectedCategory == row.category ? 1 : 0.35
    }

    private func category(matchingAmount amount: Double) -> String? {
        slices.first { abs(sliceAmount(for: $0) - amount) < 0.01 }?.category
    }

    private func sliceAmount(for row: BudgetProgress) -> Double {
        usesSpendingSlices ? row.spent : row.monthlyLimit
    }
}
