import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var goals: GoalsStore
    @EnvironmentObject private var transactions: TransactionStore

    var body: some View {
        NavigationStack {
            List {
                Section("Suggested emergency fund") {
                    Text(FinanceFormatting.currency(goals.suggestedEmergencyFund))
                        .font(.title3.bold())
                    Text("Based on 3 months of essential spending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Savings goals") {
                    if goals.savingsGoals.isEmpty {
                        Text("No savings goals yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(goals.savingsGoals) { goal in
                            SavingsGoalRow(goal: goal)
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    await goals.deleteSavingsGoal(
                                        goals.savingsGoals[index],
                                        client: auth.supabaseClient
                                    )
                                }
                            }
                        }
                    }
                    NavigationLink("Add savings goal") {
                        AddSavingsGoalView()
                    }
                }

                Section("Wealth & debt") {
                    NavigationLink("Net worth") {
                        NetWorthView()
                    }
                    NavigationLink("Debt payoff") {
                        DebtPayoffView()
                    }
                    NavigationLink("Cash flow calendar") {
                        CashFlowCalendarView()
                    }
                }
            }
            .navigationTitle("Goals")
            .task {
                await goals.reload(client: auth.supabaseClient, transactions: transactions.transactions)
            }
        }
    }
}

private struct SavingsGoalRow: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(goal.emoji ?? "🎯") \(goal.name)")
                .font(.headline)
            ProgressView(value: min(goal.currentAmount / max(goal.targetAmount, 1), 1))
            Text("\(FinanceFormatting.currency(goal.currentAmount)) of \(FinanceFormatting.currency(goal.targetAmount))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AddSavingsGoalView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var goals: GoalsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SavingsGoalDraft()

    var body: some View {
        Form {
            Section("Goal") {
                TextField("Name", text: $draft.name)
                TextField("Emoji", text: $draft.emoji)
                TextField("Target", value: $draft.targetAmount, format: .currency(code: "USD"))
                TextField("Saved so far", value: $draft.currentAmount, format: .currency(code: "USD"))
                TextField("Monthly contribution", value: $draft.monthlyContribution, format: .currency(code: "USD"))
            }
        }
        .navigationTitle("Add Goal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await goals.addSavingsGoal(draft, client: auth.supabaseClient)
                        if goals.errorMessage == nil { dismiss() }
                    }
                }
            }
        }
    }
}

struct NetWorthView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var transactions: TransactionStore

    var body: some View {
        List {
            Section("Current") {
                LabeledContent("Assets", value: FinanceFormatting.currency(netWorth.currentAssets))
                LabeledContent("Liabilities", value: FinanceFormatting.currency(netWorth.currentLiabilities))
                LabeledContent("Net worth", value: FinanceFormatting.currency(netWorth.currentNetWorth))
            }
            Section("History") {
                if netWorth.snapshots.isEmpty {
                    Text("Capture a snapshot to track trends.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(netWorth.snapshots) { snap in
                        HStack {
                            Text(snap.date)
                            Spacer()
                            Text(FinanceFormatting.currency(snap.netWorth))
                        }
                    }
                }
            }
        }
        .navigationTitle("Net Worth")
        .toolbar {
            Button("Capture snapshot") {
                Task {
                    await netWorth.captureSnapshot(
                        client: auth.supabaseClient,
                        accounts: transactions.accounts
                    )
                }
            }
        }
        .task {
            await netWorth.reload(client: auth.supabaseClient, accounts: transactions.accounts)
        }
    }
}

struct DebtPayoffView: View {
    @EnvironmentObject private var goals: GoalsStore

    @State private var draft = DebtAccountDraft()

    var body: some View {
        List {
            Section("Strategy") {
                Picker("Method", selection: $goals.debtStrategy) {
                    ForEach(DebtPayoffStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .onChange(of: goals.debtStrategy) { _, _ in goals.recomputePayoffPlan() }
                TextField("Extra monthly payment", value: $goals.extraDebtPayment, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .onSubmit { goals.recomputePayoffPlan() }
            }

            Section("Debts") {
                ForEach(goals.debtAccounts) { debt in
                    VStack(alignment: .leading) {
                        Text(debt.name).font(.headline)
                        Text("Balance \(FinanceFormatting.currency(debt.balance)) • \(String(format: "%.1f", debt.apr))% APR")
                            .font(.caption)
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { goals.debtAccounts[$0] }.forEach(goals.removeDebtAccount)
                }
            }

            Section("Add debt") {
                TextField("Name", text: $draft.name)
                TextField("Balance", value: $draft.balance, format: .currency(code: "USD"))
                TextField("APR %", value: $draft.apr, format: .number)
                TextField("Minimum payment", value: $draft.minimumPayment, format: .currency(code: "USD"))
                Button("Add") {
                    goals.addDebtAccount(draft)
                    draft = DebtAccountDraft()
                }
            }

            Section("Payoff timeline") {
                Text("Estimated payoff: \(DebtPayoffEngine.payoffMonthCount(steps: goals.payoffSteps)) months")
                ForEach(goals.payoffSteps.prefix(12)) { step in
                    Text("Month \(step.monthIndex): \(step.accountName) paid \(FinanceFormatting.currency(step.payment))")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Debt Payoff")
    }
}

struct CashFlowCalendarView: View {
    @EnvironmentObject private var transactions: TransactionStore

    private var days: [CashFlowDay] {
        CashFlowEngine.projectedDays(transactions: transactions.transactions)
    }

    var body: some View {
        List {
            summarySection(days: 30, title: "30 days")
            summarySection(days: 60, title: "60 days")
            summarySection(days: 90, title: "90 days")
            Section("Daily forecast (first 14 days)") {
                ForEach(Array(days.prefix(14))) { day in
                    HStack {
                        Text(day.date)
                        Spacer()
                        Text(FinanceFormatting.currency(day.net))
                            .foregroundStyle(day.net >= 0 ? .green : .red)
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Cash Flow")
    }

    @ViewBuilder
    private func summarySection(days count: Int, title: String) -> some View {
        let totals = CashFlowEngine.horizonTotals(days: days, first: count)
        Section(title) {
            LabeledContent("Inflow", value: FinanceFormatting.currency(totals.inflow))
            LabeledContent("Outflow", value: FinanceFormatting.currency(totals.outflow))
            LabeledContent("Net", value: FinanceFormatting.currency(totals.net))
        }
    }
}
