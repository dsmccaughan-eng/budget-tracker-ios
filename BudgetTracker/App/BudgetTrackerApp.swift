import SwiftUI

@main
struct BudgetTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var plaidLinkCoordinator = PlaidLinkCoordinator()
    @StateObject private var transactionStore = TransactionStore()
    @StateObject private var budgetStore = BudgetStore()
    @StateObject private var goalsStore = GoalsStore()
    @StateObject private var netWorthStore = NetWorthStore()
    @StateObject private var accountBalanceStore = AccountBalanceStore()
    @StateObject private var merchantRulesStore = MerchantRulesStore()
    @StateObject private var priceHistoryStore = PriceHistoryStore()
    @StateObject private var insightsStore = InsightsStore()
    @StateObject private var notificationSettingsStore = NotificationSettingsStore()
    @StateObject private var appLockStore = AppLockStore()
    @StateObject private var transactionReviewStore = TransactionReviewStore()

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
                .environmentObject(goalsStore)
                .environmentObject(netWorthStore)
                .environmentObject(accountBalanceStore)
                .environmentObject(merchantRulesStore)
                .environmentObject(priceHistoryStore)
                .environmentObject(insightsStore)
                .environmentObject(notificationSettingsStore)
                .environmentObject(transactionReviewStore)
                .task {
                    APIKeys.syncToUserDefaultsIfNeeded()
                }
                .task(id: financialDataTaskID) {
                    guard authStore.state == .authenticated,
                          appLockStore.canAccessFinancialData else { return }
                    await reloadFinancialData()
                }
                .onChange(of: authStore.state) { _, newState in
                    if newState != .authenticated {
                        appLockStore.lock()
                    }
                }
                .onChange(of: transactionStore.transactions) { _, newTransactions in
                    budgetStore.noteTransactionsChanged(newTransactions)
                }
        }
    }

    private var financialDataTaskID: String {
        "\(authStore.state)-\(appLockStore.hasPIN)-\(appLockStore.isUnlocked)-\(appLockStore.canAccessFinancialData)"
    }

    @MainActor
    private func reloadFinancialData() async {
        guard authStore.state == .authenticated, let client = authStore.activeSupabaseClient else { return }
        await transactionStore.loadAll(client: client)
        await transactionStore.refreshPlaidAccountsIfNeeded(
            client: client,
            userId: authStore.userId
        )
        await budgetStore.reload(client: client, transactions: transactionStore.transactions)
        await goalsStore.reload(client: client, transactions: transactionStore.transactions)
        await reloadNetWorthData()
        await merchantRulesStore.reload(client: client)
        await priceHistoryStore.reload(client: client)
        insightsStore.refreshLocal(transactions: transactionStore.transactions)
    }

    @MainActor
    private func reloadNetWorthData() async {
        guard authStore.state == .authenticated,
              appLockStore.canAccessFinancialData,
              let client = authStore.activeSupabaseClient else { return }
        await accountBalanceStore.reload(client: client)
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
