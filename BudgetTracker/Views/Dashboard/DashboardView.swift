import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var notifications: NotificationSettingsStore
    @EnvironmentObject private var appLock: AppLockStore

    @State private var showAddBudget = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !appLock.hasPIN {
                    Section {
                        NavigationLink {
                            SetupAppLockSettingsView(lock: appLock)
                        } label: {
                            Label("Set up Face ID and PIN", systemImage: "lock.shield")
                        }
                    } footer: {
                        Text("Protect your budget when you leave the app. You can also enable this under Settings → Security.")
                    }
                }

                Section("Net worth") {
                    NavigationLink {
                        NetWorthView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FinanceFormatting.currency(netWorth.currentNetWorth))
                                .font(.title2.weight(.bold))
                            Text("View trend chart and accounts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

                if let budgetError = budgets.errorMessage {
                    Section {
                        Text(budgetError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("Budget overview") {
                    if budgets.isLoading {
                        ProgressView("Loading budgets…")
                    } else if budgets.progress.isEmpty {
                        Text("Set monthly limits per category to track spending.")
                            .foregroundStyle(.secondary)
                        Button {
                            showAddBudget = true
                        } label: {
                            Label("Set up budgets", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        NavigationLink {
                            BudgetView()
                        } label: {
                            BudgetSpendPieChart(
                                progress: budgets.progress,
                                referenceDate: Date(),
                                hasTransactions: !transactions.transactions.isEmpty
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

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
                                    Text(TransactionFormatting.formattedAmount(transaction.amount))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(TransactionFormatting.amountColor(transaction.amount))
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showAddBudget, onDismiss: {
                Task { await reloadDashboardData() }
            }) {
                NavigationStack {
                    SetupBudgetPlanView()
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .refreshable {
                await reloadAll()
            }
            .task {
                await reloadDashboardData()
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

    private func reloadDashboardData() async {
        guard let client = auth.activeSupabaseClient else { return }
        if transactions.transactions.isEmpty {
            await transactions.loadAll(client: client)
        }
        await budgets.reload(client: client, transactions: transactions.transactions)
    }

    private func reloadAll() async {
        await reloadDashboardData()
        let alerts = BudgetAlertEngine.alerts(
            progress: budgets.progress,
            threshold: notifications.alertThreshold
        )
        notifications.scheduleBudgetAlerts(messages: alerts)
    }
}
