import Foundation
import Supabase

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var plaidItems: [PlaidItem] = []
    @Published private(set) var tellerItems: [TellerItem] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?

    private let plaidAccountRefreshStore = PlaidAccountRefreshStore()

    private var loadingRequestCount = 0
    private var inFlightLoadAll: Task<Void, Never>?

    func loadAll(client: SupabaseClient, showsLoading: Bool = true) async {
        if let inFlightLoadAll {
            await inFlightLoadAll.value
            return
        }

        let task = Task { @MainActor in
            await self.performLoadAll(client: client, showsLoading: showsLoading)
        }
        inFlightLoadAll = task
        await task.value
        inFlightLoadAll = nil
    }

    private func performLoadAll(client: SupabaseClient, showsLoading: Bool) async {
        if showsLoading {
            loadingRequestCount += 1
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showsLoading {
                loadingRequestCount = max(loadingRequestCount - 1, 0)
                if loadingRequestCount == 0 {
                    isLoading = false
                }
            }
        }

        let since = SupabaseService.transactionHistorySinceDate()

        do {
            accounts = try await SupabaseService.shared.fetchAccounts(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            transactions = try await SupabaseService.shared.fetchTransactions(
                client: client,
                since: since
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        if let rows = try? await SupabaseService.shared.fetchPlaidItems(client: client) {
            plaidItems = rows
        }

        tellerItems = (try? await SupabaseService.shared.fetchTellerItems(client: client)) ?? []
    }

    func sync(client: SupabaseClient) async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let result = try await SupabaseService.shared.syncAllTransactions(client: client)
            lastSyncSummary = "Synced \(result.synced) transactions (\(result.categorized) newly categorized)."
            await loadAll(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPlaidAccountsIfNeeded(
        client: SupabaseClient,
        userId: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard let userId else { return }
        guard PlaidAccountRefreshPolicy.hasRefreshablePlaidItems(plaidItems) else { return }
        let lastRefreshAt = plaidAccountRefreshStore.lastRefreshAt(userId: userId)
        guard PlaidAccountRefreshPolicy.shouldRefreshAutomatically(
            lastRefreshAt: lastRefreshAt,
            now: now,
            calendar: calendar
        ) else { return }
        await refreshAccountsFromPlaid(client: client, userId: userId, showsLoading: false)
    }

    func refreshAccountsFromPlaid(
        client: SupabaseClient,
        userId: String?,
        showsLoading: Bool = true
    ) async {
        if showsLoading {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            try await SupabaseService.shared.refreshPlaidAccounts(client: client)
            await loadAll(client: client, showsLoading: false)
            if let userId {
                plaidAccountRefreshStore.markRefreshed(userId: userId, at: Date())
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var bankConnections: [BankConnection] {
        plaidItems.map(BankConnection.from(plaid:)) +
            tellerItems.map(BankConnection.from(teller:))
    }

    func removeBankConnection(_ connection: BankConnection, client: SupabaseClient) async {
        switch connection.provider {
        case .plaid:
            guard let plaidItemId = connection.plaidItemId,
                  let item = plaidItems.first(where: { $0.plaidItemId == plaidItemId }) else { return }
            await removePlaidItem(item, client: client)
        case .teller:
            guard let enrollmentId = connection.tellerEnrollmentId else { return }
            await removeTellerItem(enrollmentId: enrollmentId, client: client)
        }
    }

    func removeTellerItem(enrollmentId: String, client: SupabaseClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.removeTellerItem(
                tellerEnrollmentId: enrollmentId,
                client: client
            )
            await loadAll(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePlaidItem(_ item: PlaidItem, client: SupabaseClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.removePlaidItem(
                plaidItemId: item.plaidItemId,
                client: client
            )
            await loadAll(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(
        transaction: Transaction,
        category: String,
        saveMerchantRule: Bool = false,
        merchantRules: MerchantRulesStore? = nil,
        client: SupabaseClient
    ) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateTransactionCategory(
                id: transaction.id,
                category: category,
                subcategory: transaction.subcategory,
                client: client
            )
            replaceTransaction(id: transaction.id) { txn in
                txn.category = category
                txn.categorySource = CategorySource.user.rawValue
            }
            if saveMerchantRule, let merchantRules {
                try await merchantRules.upsertRule(for: transaction, category: category, client: client)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBillSettings(
        transaction: Transaction,
        isFixedBill: Bool,
        billNickname: String?,
        billDueDay: Int?,
        billAmount: Double?,
        client: SupabaseClient
    ) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateTransactionBillSettings(
                id: transaction.id,
                isFixedBill: isFixedBill,
                billNickname: billNickname,
                billDueDay: billDueDay,
                billAmount: billAmount,
                client: client
            )
            replaceTransaction(id: transaction.id) { txn in
                txn.isFixedBill = isFixedBill
                txn.billNickname = billNickname
                txn.billDueDay = billDueDay
                txn.billAmount = billAmount
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBudgetExclusion(
        transaction: Transaction,
        excludedFromBudget: Bool,
        client: SupabaseClient
    ) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateTransactionBudgetExclusion(
                id: transaction.id,
                excludedFromBudget: excludedFromBudget,
                client: client
            )
            replaceTransaction(id: transaction.id) { txn in
                txn.excludedFromBudget = excludedFromBudget
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceTransaction(id: UUID, mutate: (inout Transaction) -> Void) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { return }
        var updated = transactions
        mutate(&updated[index])
        transactions = updated
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    func filteredTransactions(search: String, category: String?) -> [Transaction] {
        transactions.filter { txn in
            let matchesCategory = category.map { txn.category == $0 } ?? true
            guard matchesCategory else { return false }
            guard !search.isEmpty else { return true }
            let haystack = [
                FinanceFormatting.displayName(for: txn),
                txn.category,
                txn.name
            ].joined(separator: " ").lowercased()
            return haystack.contains(search.lowercased())
        }
    }

    func saveReceiptResult(_ receipt: ReceiptParseResult, client: SupabaseClient) async {
        errorMessage = nil
        guard let account = accounts.first else {
            errorMessage = BudgetTrackerError.server("Link an account before saving receipt purchases.").localizedDescription
            return
        }
        do {
            let txn = Transaction(
                id: UUID(),
                accountId: account.id,
                plaidTransactionId: "manual-\(UUID().uuidString)",
                amount: receipt.total,
                date: receipt.date,
                merchantName: receipt.merchant,
                name: receipt.merchant,
                category: receipt.items.first?.category ?? "Shopping",
                subcategory: nil,
                pending: false,
                isManual: true,
                splitItems: nil
            )
            let saved = try await SupabaseService.shared.saveManualTransaction(txn, client: client)
            transactions.insert(saved, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSplit(transaction: Transaction, splitItems: [SplitItem], client: SupabaseClient) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateTransactionSplits(
                id: transaction.id,
                splitItems: splitItems,
                client: client
            )
            replaceTransaction(id: transaction.id) { txn in
                txn.splitItems = splitItems
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
