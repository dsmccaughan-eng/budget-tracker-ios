import Foundation
import Supabase

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var plaidItems: [PlaidItem] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?

    func loadAll(client: SupabaseClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let accountRows = SupabaseService.shared.fetchAccounts(client: client)
            async let plaidItemRows = SupabaseService.shared.fetchPlaidItems(client: client)
            let since = SupabaseService.transactionHistorySinceDate()
            async let transactionRows = SupabaseService.shared.fetchTransactions(
                client: client,
                since: since
            )
            accounts = try await accountRows
            plaidItems = try await plaidItemRows
            transactions = try await transactionRows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync(client: SupabaseClient) async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let result = try await SupabaseService.shared.syncTransactions(client: client)
            lastSyncSummary = "Synced \(result.synced) transactions (\(result.categorized) newly categorized)."
            await loadAll(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccountsFromPlaid(client: SupabaseClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.refreshPlaidAccounts(client: client)
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
