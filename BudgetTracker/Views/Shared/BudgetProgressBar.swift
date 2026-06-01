import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            r = 0.23
            g = 0.51
            b = 0.96
        }
        self.init(red: r, green: g, blue: b)
    }
}

struct BudgetProgressBar: View {
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.category)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(FinanceFormatting.currency(progress.spent)) / \(FinanceFormatting.currency(progress.monthlyLimit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(progress.isOverBudget ? Color.red : Color(hex: progress.color))
                        .frame(width: geo.size.width * min(progress.percentUsed, 1))
                }
            }
            .frame(height: 8)
            if !progress.isFixed {
                Text("Typical: \(FinanceFormatting.currency(progress.projectedSpend))")
                    .font(.caption2)
                    .foregroundStyle(progress.projectedSpend > progress.monthlyLimit ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
