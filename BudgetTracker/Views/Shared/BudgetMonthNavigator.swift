import SwiftUI

struct BudgetMonthNavigator: View {
    @Binding var monthOffset: Int
    var calendar: Calendar = .current

    private var selectedMonth: Date {
        let current = BudgetMath.startOfMonth(Date(), calendar: calendar)
        return calendar.date(byAdding: .month, value: -monthOffset, to: current) ?? current
    }

    private var canGoForward: Bool {
        monthOffset > 0
    }

    var body: some View {
        HStack {
            Button {
                monthOffset += 1
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
                .id(monthOffset)

            Spacer()

            Button {
                if monthOffset > 0 {
                    monthOffset -= 1
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(canGoForward ? Color.secondary : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 4)
    }
}
