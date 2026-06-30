import Foundation
import Supabase

extension TransactionStore {
    func sync(client: SupabaseClient, userId: String?) async {
        if let inFlightBackgroundMaintenance {
            await inFlightBackgroundMaintenance.value
        }
        if let inFlightSyncIfNeeded {
            await inFlightSyncIfNeeded.value
        }
        guard !isSyncing else { return }

        beginTransactionSync()
        errorMessage = nil
        defer { endTransactionSync() }

        var syncedCount = 0
        var recategorizedCount = 0
        do {
            let result = try await SupabaseService.shared.syncAllTransactions(client: client)
            syncedCount = result.synced
            recategorizedCount = result.recategorized ?? 0
            if result.synced > 0 {
                lastSyncSummary = "Synced \(result.synced) transactions (\(result.categorized) newly categorized)."
            } else if recategorizedCount > 0 {
                lastSyncSummary = "Recategorized \(recategorizedCount) transactions."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if recategorizedCount == 0 {
            if let recategorized = try? await SupabaseService.shared.recategorizeTransactions(
                client: client
            ), recategorized.categorized > 0 {
                recategorizedCount = recategorized.categorized
                lastSyncSummary = "Recategorized \(recategorized.categorized) transactions."
            }
        }

        await loadAll(client: client, showsLoading: false)
        if let userId {
            let now = Date()
            if TransactionSyncPolicy.shouldRecordClientSync(
                syncedCount: syncedCount,
                transactions: transactions,
                now: now
            ) {
                transactionSyncStore.markSynced(userId: userId, at: now)
            }
        }
    }

    @discardableResult
    func runBackgroundMaintenance(
        client: SupabaseClient,
        userId: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        if let inFlightBackgroundMaintenance {
            return await inFlightBackgroundMaintenance.value
        }

        let task = Task { @MainActor in
            await self.performBackgroundMaintenance(
                client: client,
                userId: userId,
                now: now,
                calendar: calendar
            )
        }
        inFlightBackgroundMaintenance = task
        let result = await task.value
        inFlightBackgroundMaintenance = nil
        return result
    }

    @discardableResult
    func syncIfNeeded(
        client: SupabaseClient,
        userId: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        if let inFlightSyncIfNeeded {
            return await inFlightSyncIfNeeded.value
        }

        let task = Task { @MainActor in
            await self.performSyncIfNeeded(
                client: client,
                userId: userId,
                now: now,
                calendar: calendar
            )
        }
        inFlightSyncIfNeeded = task
        let result = await task.value
        inFlightSyncIfNeeded = nil
        return result
    }

    func performBackgroundMaintenance(
        client: SupabaseClient,
        userId: String?,
        now: Date,
        calendar: Calendar
    ) async -> Bool {
        let didSync = await syncIfNeeded(
            client: client,
            userId: userId,
            now: now,
            calendar: calendar
        )
        let refreshedPlaid = await refreshPlaidAccountsIfNeeded(
            client: client,
            userId: userId,
            now: now,
            calendar: calendar
        )
        await refreshAccountsIfMissing(client: client, userId: userId)
        return didSync || refreshedPlaid
    }

    func performSyncIfNeeded(
        client: SupabaseClient,
        userId: String?,
        now: Date,
        calendar: Calendar
    ) async -> Bool {
        guard !isSyncing else { return false }
        guard let userId else { return false }
        let lastClientSyncAt = transactionSyncStore.lastSyncAt(userId: userId)
        guard TransactionSyncPolicy.shouldSyncAutomatically(
            lastClientSyncAt: lastClientSyncAt,
            plaidItems: plaidItems,
            tellerItems: tellerItems,
            transactions: transactions,
            now: now,
            calendar: calendar
        ) else {
            return false
        }

        beginTransactionSync()
        errorMessage = nil
        defer { endTransactionSync() }

        var syncedCount = 0
        var recategorizedCount = 0
        do {
            let result = try await SupabaseService.shared.syncAllTransactions(client: client)
            syncedCount = result.synced
            recategorizedCount = result.recategorized ?? 0
            if result.synced > 0 {
                lastSyncSummary = "Synced \(result.synced) transactions (\(result.categorized) newly categorized)."
            } else if recategorizedCount > 0 {
                lastSyncSummary = "Recategorized \(recategorizedCount) transactions."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if recategorizedCount == 0 {
            if let recategorized = try? await SupabaseService.shared.recategorizeTransactions(
                client: client
            ), recategorized.categorized > 0 {
                recategorizedCount = recategorized.categorized
                lastSyncSummary = "Recategorized \(recategorized.categorized) transactions."
            }
        }

        await loadAll(client: client, showsLoading: false)
        if TransactionSyncPolicy.shouldRecordClientSync(
            syncedCount: syncedCount,
            transactions: transactions,
            now: now,
            calendar: calendar
        ) {
            transactionSyncStore.markSynced(userId: userId, at: Date())
        } else if syncedCount == 0, errorMessage == nil {
            lastSyncSummary = "Bank sync completed but no new transactions arrived yet."
        }
        return true
    }
}
