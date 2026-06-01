import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var notifications: NotificationSettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Net worth") {
                    LabeledContent("Today", value: FinanceFormatting.currency(netWorth.currentNetWorth))
                    NavigationLink("Net worth details") {
                        NetWorthView()
                    }
                }

                Section("Alerts") {
                    let alerts = BudgetAlertEngine.alerts(
                        progress: budgets.progress,
                        threshold: notifications.alertThreshold
                    )
                    if alerts.isEmpty {
                        Text("No budget alerts right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts, id: \.self) { alert in
                            Label(alert, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Bills") {
                    if monthlyBills.isEmpty {
                        Text("Mark a budget as a fixed expense to see due dates here.")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            BillsListView()
                        } label: {
                            Label(billsSummaryLabel, systemImage: "calendar")
                        }
                        ForEach(monthlyBills.prefix(3)) { bill in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(bill.displayDue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(FinanceFormatting.currency(bill.amount))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }

                Section("Budget overview") {
                    if budgets.progress.isEmpty {
                        Text("Set monthly limits per category to track spending.")
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            AddBudgetView()
                        } label: {
                            Label("Set up budgets", systemImage: "plus.circle.fill")
                        }
                    } else {
                        BudgetRingSummary(percentUsed: BudgetMath.totalBudgetUsedPercent(budgets.progress))
                        ForEach(budgets.progress.prefix(3)) { row in
                            BudgetProgressBar(progress: row)
                        }
                        NavigationLink("View all budgets") {
                            BudgetView()
                        }
                    }
                }

                Section("Recent transactions") {
                    if recentTransactions.isEmpty {
                        Text("Sync transactions from the Transactions tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentTransactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(FinanceFormatting.displayName(for: transaction))
                                        Text(transaction.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(FinanceFormatting.currency(abs(transaction.amount)))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                }

                Section("Accounts") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label("\(transactions.accounts.count) linked accounts", systemImage: "building.columns")
                    }
                    NavigationLink {
                        PlaidLinkView()
                    } label: {
                        Label("Connect bank", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await reloadAll()
            }
            .task {
                await netWorth.reload(client: auth.supabaseClient, accounts: transactions.accounts)
            }
        }
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.transactions.prefix(5))
    }

    private var monthlyBills: [BillItem] {
        BillsEngine.bills(
            budgets: budgets.budgets,
            transactions: transactions.transactions
        )
    }

    private var billsSummaryLabel: String {
        let dueCount = monthlyBills.filter { !$0.isPaid }.count
        if dueCount == 0 {
            return "All bills paid this month"
        }
        return "\(dueCount) bill\(dueCount == 1 ? "" : "s") due this month"
    }

    private func reloadAll() async {
        await transactions.loadAll(client: auth.supabaseClient)
        await budgets.reload(client: auth.supabaseClient, transactions: transactions.transactions)
        await netWorth.reload(client: auth.supabaseClient, accounts: transactions.accounts)
        let alerts = BudgetAlertEngine.alerts(
            progress: budgets.progress,
            threshold: notifications.alertThreshold
        )
        notifications.scheduleBudgetAlerts(messages: alerts)
    }
}

private struct BudgetRingSummary: View {
    let percentUsed: Double

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: percentUsed)
                    .stroke(percentUsed > 1 ? Color.red : Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percentUsed * 100))%")
                    .font(.title3.bold())
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly budget used")
                    .font(.headline)
                Text(percentUsed > 1 ? "Over budget" : "On track")
                    .font(.caption)
                    .foregroundStyle(percentUsed > 1 ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
