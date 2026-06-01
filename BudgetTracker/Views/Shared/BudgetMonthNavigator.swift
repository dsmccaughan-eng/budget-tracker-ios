import SwiftUI

struct BudgetMonthNavigator: View {
    @Binding var selectedMonth: Date
    var calendar: Calendar = .current

    private var canGoForward: Bool {
        let selected = BudgetMath.startOfMonth(selectedMonth, calendar: calendar)
        let current = BudgetMath.startOfMonth(Date(), calendar: calendar)
        return selected < current
    }

    var body: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(BudgetMath.startOfMonth(selectedMonth, calendar: calendar), format: .dateTime.month(.wide).year())
                .font(.headline)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(canGoForward ? Color.secondary : Color.secondary.opacity(0.35))
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 4)
    }

    private func shiftMonth(by value: Int) {
        let anchor = BudgetMath.startOfMonth(selectedMonth, calendar: calendar)
        if let next = calendar.date(byAdding: .month, value: value, to: anchor) {
            selectedMonth = next
        }
    }
}
