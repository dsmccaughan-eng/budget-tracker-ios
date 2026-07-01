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

    @Binding var selectedTab: AppTab

    @State private var showAddBudget = false
    @State private var showSettings = false
    @State private var showReviewConfirmed = false
    @State private var unreviewedExpanded = false

    private var dashboardSpendingProgress: [BudgetProgress] {
        _ = budgets.spendDataVersion
        return budgets.spendingProgress(transactions: transactions.transactions)
    }

    private var dashboardBudgetSpent: Double {
        BudgetMath.monthSpendingDisplayTotal(progress: dashboardSpendingProgress)
    }

    private var dashboardBudgetLimit: Double {
        budgets.budgets.reduce(0) { $0 + $1.monthlyLimit }
    }

    private var dashboardBudgetAlerts: [String] {
        BudgetAlertEngine.alerts(
            progress: budgets.progress,
            transactions: transactions.transactions,
            threshold: notifications.alertThreshold
        )
    }

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

                Section("Budget") {
                    if budgets.isLoading {
                        ProgressView("Loading budgets…")
                    } else if budgets.budgets.isEmpty {
                        Text("Set monthly limits per category to track spending.")
                            .foregroundStyle(.secondary)
                        Button {
                            showAddBudget = true
                        } label: {
                            Label("Set up budgets", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        DashboardBudgetSummary(
                            spent: dashboardBudgetSpent,
                            budget: dashboardBudgetLimit,
                            onViewFullBudget: { selectedTab = .budgets }
                        )
                    }
                }

                Section("Alerts") {
                    if dashboardBudgetAlerts.isEmpty {
                        Text("No budget alerts right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dashboardBudgetAlerts, id: \.self) { alert in
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

                Section {
                    if unreviewedTransactions.isEmpty {
                        Text("You're caught up. New synced transactions will appear here for review.")
                            .foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup(isExpanded: $unreviewedExpanded) {
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
                        } label: {
                            HStack {
                                Text("Unreviewed transactions")
                                Spacer()
                                Text("\(unreviewedTransactions.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !unreviewedExpanded && unreviewedTransactions.count > 3 {
                            Text("Tap to expand and review categories.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if !unreviewedTransactions.isEmpty && unreviewedExpanded {
                        Text("Tap each transaction to verify its category, then confirm when you're done.")
                    }
                }

                Section("Accounts") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label(accountsSummaryLabel, systemImage: "building.columns")
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
            .task {
                guard auth.activeSupabaseClient != nil else { return }
                guard transactions.accounts.isEmpty,
                      !transactions.bankConnections.isEmpty || !transactions.transactions.isEmpty else { return }
                guard let client = auth.activeSupabaseClient else { return }
                await transactions.refreshAccountsIfMissing(
                    client: client,
                    userId: auth.userId
                )
            }
            .onAppear {
                applyUnreviewedExpansionPolicy(count: unreviewedTransactions.count)
            }
            .onChange(of: unreviewedTransactions.count) { oldCount, newCount in
                if newCount == 0 {
                    unreviewedExpanded = false
                } else if oldCount > 3 && newCount <= 3 {
                    unreviewedExpanded = true
                } else if oldCount <= 3 && newCount > 3 {
                    unreviewedExpanded = false
                }
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

    private var accountsSummaryLabel: String {
        let accountCount = transactions.accounts.count
        if accountCount > 0 {
            return "\(accountCount) linked account\(accountCount == 1 ? "" : "s")"
        }
        let connectionCount = transactions.bankConnections.count
        if connectionCount > 0 {
            return "\(connectionCount) bank connection\(connectionCount == 1 ? "" : "s")"
        }
        return "No accounts linked"
    }

    private func applyUnreviewedExpansionPolicy(count: Int) {
        unreviewedExpanded = count > 0 && count <= 3
    }

    private func reloadDashboardData() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.loadAll(client: client)
        await transactions.refreshPlaidAccountsIfNeeded(
            client: client,
            userId: auth.userId
        )
        await transactions.refreshAccountsIfMissing(
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
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.sync(client: client, userId: auth.userId)
        await reloadDashboardData()
        let alerts = BudgetAlertEngine.alerts(
            progress: budgets.progress,
            transactions: transactions.transactions,
            threshold: notifications.alertThreshold
        )
        notifications.scheduleBudgetAlerts(messages: alerts)
    }
}
