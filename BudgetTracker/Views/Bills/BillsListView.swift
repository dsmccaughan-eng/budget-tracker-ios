import SwiftUI

struct BillsListView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    @State private var selectedDay: Int?
    @State private var showAddBudget = false

    private var bills: [BillItem] {
        BillsEngine.bills(
            budgets: budgets.budgets,
            transactions: transactions.transactions
        )
    }

    private var billDays: Set<Int> {
        BillsEngine.daysWithBills(bills)
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    var body: some View {
        List {
            if bills.isEmpty {
                ContentUnavailableView {
                    Label("No bills yet", systemImage: "calendar")
                } description: {
                    Text("Turn on “Fixed expense” when adding a budget to track rent, utilities, and other monthly bills with due dates.")
                } actions: {
                    Button("Add budget") {
                        showAddBudget = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    monthCalendarStrip
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                Section {
                    ForEach(bills) { bill in
                        BillRowView(
                            bill: bill,
                            isHighlighted: selectedDay == bill.dueDay
                        )
                    }
                } header: {
                    HStack {
                        Text(monthRangeHeader)
                        Spacer()
                        Text(FinanceFormatting.currency(bills.reduce(0) { $0 + $1.amount }))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("Bills")
        .sheet(isPresented: $showAddBudget) {
            NavigationStack {
                SetupBudgetPlanView()
            }
        }
        .refreshable {
            guard let client = auth.activeSupabaseClient else { return }
            await transactions.loadAll(client: client)
            await budgets.reload(client: client, transactions: transactions.transactions)
        }
        .onAppear {
            if selectedDay == nil {
                selectedDay = Calendar.current.component(.day, from: Date())
            }
        }
    }

    private var monthRangeHeader: String {
        Date().formatted(.dateTime.month(.abbreviated).year())
    }

    private var monthCalendarStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date().formatted(.dateTime.month(.wide)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...daysInMonth, id: \.self) { day in
                        calendarDayButton(day: day)
                    }
                }
            }
        }
    }

    private func calendarDayButton(day: Int) -> some View {
        let isSelected = selectedDay == day
        let hasBill = billDays.contains(day)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : Color.clear)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .clipShape(Circle())
                if hasBill {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BillRowView: View {
    let bill: BillItem
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: bill.color))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .font(.subheadline.weight(.semibold))
                Text(bill.displayDue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(FinanceFormatting.currency(bill.amount))
                    .font(.subheadline.weight(.semibold))
                if bill.isPaid {
                    Text("PAID")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("Due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.08) : nil)
    }
}
