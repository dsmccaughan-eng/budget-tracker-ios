import SwiftUI

@main
struct BudgetTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var transactionStore = TransactionStore()
    @StateObject private var budgetStore = BudgetStore()
    @StateObject private var goalsStore = GoalsStore()
    @StateObject private var netWorthStore = NetWorthStore()
    @StateObject private var merchantRulesStore = MerchantRulesStore()
    @StateObject private var priceHistoryStore = PriceHistoryStore()
    @StateObject private var insightsStore = InsightsStore()
    @StateObject private var notificationSettingsStore = NotificationSettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .environmentObject(transactionStore)
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
                .task(id: authStore.state) {
                    guard authStore.state == .authenticated else { return }
                    await reloadFinancialData()
                }
        }
    }

    @MainActor
    private func reloadFinancialData() async {
        guard authStore.state == .authenticated else { return }
        let client = authStore.supabaseClient
        await transactionStore.loadAll(client: client)
        await budgetStore.reload(client: client, transactions: transactionStore.transactions)
        await goalsStore.reload(client: client, transactions: transactionStore.transactions)
        await netWorthStore.reload(client: client, accounts: transactionStore.accounts)
        await merchantRulesStore.reload(client: client)
        await priceHistoryStore.reload(client: client)
        insightsStore.refreshLocal(transactions: transactionStore.transactions)
    }
}
