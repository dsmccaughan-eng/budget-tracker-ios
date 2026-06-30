import SwiftUI

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
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await refreshDailyNetWorthIfNeeded() }
                }
        }
    }

    private var financialDataTaskID: String {
        "\(authStore.state)-\(appLockStore.hasPIN)-\(appLockStore.isUnlocked)-\(appLockStore.canAccessFinancialData)"
    }

    @MainActor
    private func reloadFinancialData() async {
        guard authStore.state == .authenticated, let client = authStore.activeSupabaseClient else { return }

        await transactionStore.loadAll(client: client, showsLoading: false)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await self.investmentStore.loadAll(client: client)
            }
            group.addTask { @MainActor in
                await self.budgetStore.reload(
                    client: client,
                    transactions: self.transactionStore.transactions,
                    showsLoading: false
                )
            }
            group.addTask { @MainActor in
                await self.merchantRulesStore.reload(client: client)
            }
            group.addTask { @MainActor in
                await self.accountBalanceStore.reload(client: client)
            }
        }

        await reloadNetWorthData()
        runBackgroundFinancialMaintenance()
    }

    @MainActor
    private func refreshDailyNetWorthIfNeeded() async {
        guard authStore.state == .authenticated,
              appLockStore.canAccessFinancialData,
              let client = authStore.activeSupabaseClient else { return }
        let didUpdate = await transactionStore.runBackgroundMaintenance(
            client: client,
            userId: authStore.userId
        )
        if didUpdate {
            await refreshDerivedFinancialData(client: client)
        }
    }

    @MainActor
    private func runBackgroundFinancialMaintenance() {
        Task { @MainActor in
            guard authStore.state == .authenticated,
                  appLockStore.canAccessFinancialData,
                  let client = authStore.activeSupabaseClient else { return }

            let didUpdate = await transactionStore.runBackgroundMaintenance(
                client: client,
                userId: authStore.userId
            )
            if didUpdate {
                await refreshDerivedFinancialData(client: client)
            }
        }
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
