import SwiftUI
import Supabase

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore
    @EnvironmentObject private var notifications: NotificationSettingsStore
    @EnvironmentObject private var appLock: AppLockStore
    @EnvironmentObject private var transactionReview: TransactionReviewStore

    @State private var showAddBudget = false
    @State private var showSettings = false
    @State private var showReviewConfirmed = false

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
                        Text("Mark a transaction as a fixed monthly expense to see due dates here.")
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

                Section {
                    if unreviewedTransactions.isEmpty {
                        Text("You're caught up. New synced transactions will appear here for review.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unreviewedTransactions) { transaction in
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

                        Button("Confirm all categorized") {
                            transactionReview.markAllReviewed(transactions: transactions.transactions)
                            showReviewConfirmed = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Unreviewed transactions")
                } footer: {
                    if !unreviewedTransactions.isEmpty {
                        Text("Tap each transaction to verify its category, then confirm when you're done.")
                    }
                }

                Section("Accounts") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label("\(transactions.accounts.count) linked accounts", systemImage: "building.columns")
                    }
                    NavigationLink {
                        BankLinkView()
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
            .task(id: auth.userId) {
                transactionReview.setActiveUser(auth.userId)
            }
            .alert("Review complete", isPresented: $showReviewConfirmed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("New transactions will appear here after your next sync.")
            }
        }
    }

    private var unreviewedTransactions: [Transaction] {
        transactionReview.unreviewed(from: transactions.transactions)
    }

    private var monthlyBills: [BillItem] {
        BillsEngine.bills(
            transactions: transactions.transactions,
            budgets: budgets.budgets
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
        await transactions.loadAll(client: client)
        await transactions.refreshPlaidAccountsIfNeeded(
            client: client,
            userId: auth.userId
        )
        await budgets.reload(client: client, transactions: transactions.transactions)
        await reloadNetWorth(client: client)
    }

    private func reloadNetWorth(client: SupabaseClient) async {
        await accountBalances.reload(client: client)
        await netWorth.reload(
            client: client,
            accounts: transactions.accounts,
            accountSnapshots: accountBalances.snapshots,
            transactions: transactions.transactions
        )
        await netWorth.recordDailySnapshotIfNeeded(
            client: client,
            accounts: transactions.accounts,
            accountBalances: accountBalances
        )
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
