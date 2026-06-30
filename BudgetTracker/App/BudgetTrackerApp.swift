import SwiftUI
import Supabase

@main
struct BudgetTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authStore = AuthStore()
    @StateObject private var plaidLinkCoordinator = PlaidLinkCoordinator()
    @StateObject private var transactionStore = TransactionStore()
    @StateObject private var budgetStore = BudgetStore()
    @StateObject private var netWorthStore = NetWorthStore()
    @StateObject private var accountBalanceStore = AccountBalanceStore()
    @StateObject private var merchantRulesStore = MerchantRulesStore()
    @StateObject private var notificationSettingsStore = NotificationSettingsStore()
    @StateObject private var appLockStore = AppLockStore()
    @StateObject private var transactionReviewStore = TransactionReviewStore()
    @StateObject private var investmentStore = InvestmentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .environmentObject(appLockStore)
                .environmentObject(plaidLinkCoordinator)
                .environmentObject(transactionStore)
                .onOpenURL { url in
                    _ = plaidLinkCoordinator.continueLink(from: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    _ = plaidLinkCoordinator.continueLink(from: url)
                }
                .environmentObject(budgetStore)
                .environmentObject(netWorthStore)
                .environmentObject(accountBalanceStore)
                .environmentObject(merchantRulesStore)
                .environmentObject(notificationSettingsStore)
                .environmentObject(transactionReviewStore)
                .environmentObject(investmentStore)
                .task {
                    APIKeys.syncToUserDefaultsIfNeeded()
                }
                .task(id: financialDataTaskID) {
                    guard authStore.state == .authenticated,
                          appLockStore.canAccessFinancialData else { return }
                    await beginFinancialSession()
                }
                .onChange(of: authStore.state) { _, newState in
                    if newState != .authenticated {
                        appLockStore.lock()
                    }
                }
                .onChange(of: transactionStore.transactions) { _, newTransactions in
                    Task { @MainActor in
                        budgetStore.noteTransactionsChanged(newTransactions)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await refreshOnForeground() }
                }
        }
    }

    private var financialDataTaskID: String {
        "\(authStore.state)-\(appLockStore.hasPIN)-\(appLockStore.isUnlocked)-\(appLockStore.canAccessFinancialData)"
    }

    @MainActor
    private func beginFinancialSession() async {
        guard authStore.state == .authenticated, let client = authStore.activeSupabaseClient else { return }

        transactionStore.beginFinancialBootstrap()
        defer { transactionStore.endFinancialBootstrap() }

        await transactionStore.loadAll(client: client, showsLoading: false)
        applyLocalDerivedState()

        if transactionStore.needsAutomaticSync(userId: authStore.userId) {
            _ = await transactionStore.syncIfNeeded(
                client: client,
                userId: authStore.userId
            )
            applyLocalDerivedState()
        }

        Task { @MainActor in
            await loadSecondaryFinancialData(client: client)
        }
    }

    @MainActor
    private func refreshOnForeground() async {
        guard authStore.state == .authenticated,
              appLockStore.canAccessFinancialData,
              let client = authStore.activeSupabaseClient else { return }

        if TransactionSyncPolicy.transactionsAppearStale(
            transactions: transactionStore.transactions,
            now: Date()
        ) {
            await transactionStore.loadAll(client: client, showsLoading: false)
            applyLocalDerivedState()
        }

        if transactionStore.needsAutomaticSync(userId: authStore.userId) {
            let didSync = await transactionStore.syncIfNeeded(
                client: client,
                userId: authStore.userId
            )
            if didSync {
                applyLocalDerivedState()
                await refreshDerivedFinancialData(client: client)
            }
            return
        }

        let didUpdate = await transactionStore.runBackgroundMaintenance(
            client: client,
            userId: authStore.userId
        )
        if didUpdate {
            applyLocalDerivedState()
            await refreshDerivedFinancialData(client: client)
        }
    }

    @MainActor
    private func applyLocalDerivedState() {
        budgetStore.noteTransactionsChanged(transactionStore.transactions)
        netWorthStore.syncFromLocal(
            accounts: transactionStore.accounts,
            accountSnapshots: accountBalanceStore.snapshots,
            transactions: transactionStore.transactions
        )
    }

    @MainActor
    private func loadSecondaryFinancialData(client: SupabaseClient) async {
        async let budgets: Void = budgetStore.reload(
            client: client,
            transactions: transactionStore.transactions,
            showsLoading: false
        )
        async let investments: Void = investmentStore.loadAll(client: client)
        async let rules: Void = merchantRulesStore.reload(client: client)
        async let balances: Void = accountBalanceStore.reload(client: client)
        _ = await (budgets, investments, rules, balances)

        await reloadNetWorthData()
        _ = await transactionStore.runBackgroundMaintenance(
            client: client,
            userId: authStore.userId
        )
        applyLocalDerivedState()
    }

    @MainActor
    private func refreshDerivedFinancialData(client: SupabaseClient) async {
        await budgetStore.reload(
            client: client,
            transactions: transactionStore.transactions,
            showsLoading: false
        )
        await reloadNetWorthData()
        await investmentStore.loadAll(client: client)
    }

    @MainActor
    private func reloadNetWorthData() async {
        guard authStore.state == .authenticated,
              appLockStore.canAccessFinancialData,
              let client = authStore.activeSupabaseClient else { return }
        await netWorthStore.reload(
            client: client,
            accounts: transactionStore.accounts,
            accountSnapshots: accountBalanceStore.snapshots,
            transactions: transactionStore.transactions
        )
        await netWorthStore.recordDailySnapshotIfNeeded(
            client: client,
            accounts: transactionStore.accounts,
            accountBalances: accountBalanceStore
        )
    }
}
