import SwiftUI

@main
struct BudgetTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var plaidLinkCoordinator = PlaidLinkCoordinator()
    @StateObject private var transactionStore = TransactionStore()
    @StateObject private var budgetStore = BudgetStore()
    @StateObject private var goalsStore = GoalsStore()
    @StateObject private var netWorthStore = NetWorthStore()
    @StateObject private var merchantRulesStore = MerchantRulesStore()
    @StateObject private var priceHistoryStore = PriceHistoryStore()
    @StateObject private var insightsStore = InsightsStore()
    @StateObject private var notificationSettingsStore = NotificationSettingsStore()
    @StateObject private var appLockStore = AppLockStore()

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
                .environmentObject(merchantRulesStore)
                .environmentObject(priceHistoryStore)
                .environmentObject(insightsStore)
                .environmentObject(notificationSettingsStore)
                .task {
                    APIKeys.syncToUserDefaultsIfNeeded()
                }
                .task(id: financialDataTaskID) {
                    guard authStore.state == .authenticated,
                          appLockStore.hasPIN,
                          appLockStore.isUnlocked else { return }
                    await reloadFinancialData()
                }
                .onChange(of: authStore.state) { _, newState in
                    if newState != .authenticated {
                        appLockStore.lock()
                    }
                }
        }
    }

    private var financialDataTaskID: String {
        "\(authStore.state)-\(appLockStore.hasPIN)-\(appLockStore.isUnlocked)"
    }

    @MainActor
    private func reloadFinancialData() async {
        guard authStore.state == .authenticated, let client = authStore.activeSupabaseClient else { return }
        await transactionStore.loadAll(client: client)
        await budgetStore.reload(client: client, transactions: transactionStore.transactions)
        await goalsStore.reload(client: client, transactions: transactionStore.transactions)
        await netWorthStore.reload(client: client, accounts: transactionStore.accounts)
        await merchantRulesStore.reload(client: client)
        await priceHistoryStore.reload(client: client)
        insightsStore.refreshLocal(transactions: transactionStore.transactions)
    }
}
