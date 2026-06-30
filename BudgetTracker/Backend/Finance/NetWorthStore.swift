import Foundation
import Supabase

@MainActor
final class NetWorthStore: ObservableObject {
    @Published private(set) var snapshots: [NetWorthSnapshot] = []
    @Published private(set) var currentAssets: Double = 0
    @Published private(set) var currentLiabilities: Double = 0
    @Published private(set) var currentNetWorth: Double = 0
    @Published private(set) var cachedAccounts: [Account] = []
    @Published private(set) var cachedChartPoints: [NetWorthTimeRange: [NetWorthChartPoint]] = [:]
    @Published var errorMessage: String?

    private var chartRebuildTask: Task<Void, Never>?

    func reload(
        client: SupabaseClient,
        accounts: [Account],
        accountSnapshots: [AccountBalanceSnapshot] = [],
        transactions: [Transaction] = []
    ) async {
        errorMessage = nil
        cachedAccounts = accounts
        let totals = NetWorthCalculator.totals(from: accounts)
        currentAssets = totals.assets
        currentLiabilities = totals.liabilities
        currentNetWorth = totals.net
        do {
            snapshots = try await SupabaseService.shared.fetchNetWorthSnapshots(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
        updateChartInputs(
            accounts: accounts,
            accountSnapshots: accountSnapshots,
            transactions: transactions
        )
    }

    func syncFromLocal(
        accounts: [Account],
        accountSnapshots: [AccountBalanceSnapshot],
        transactions: [Transaction]
    ) {
        cachedAccounts = accounts
        let totals = NetWorthCalculator.totals(from: accounts)
        currentAssets = totals.assets
        currentLiabilities = totals.liabilities
        currentNetWorth = totals.net
        updateChartInputs(
            accounts: accounts,
            accountSnapshots: accountSnapshots,
            transactions: transactions
        )
    }

    func chartPoints(range: NetWorthTimeRange, referenceDate: Date = Date()) -> [NetWorthChartPoint] {
        if let cached = cachedChartPoints[range], referenceDateIsToday(referenceDate) {
            return cached
        }
        return computeChartPoints(range: range, referenceDate: referenceDate)
    }

    private func referenceDateIsToday(_ referenceDate: Date) -> Bool {
        Calendar.current.isDateInToday(referenceDate)
    }

    private func computeChartPoints(
        range: NetWorthTimeRange,
        referenceDate: Date
    ) -> [NetWorthChartPoint] {
        guard let inputs = cachedChartInputs else {
            return NetWorthHistoryEngine.chartPoints(
                snapshots: snapshots,
                currentAssets: currentAssets,
                currentLiabilities: currentLiabilities,
                currentNetWorth: currentNetWorth,
                referenceDate: referenceDate,
                range: range
            )
        }
        return NetWorthHistoryEngine.chartPoints(
            snapshots: snapshots,
            accounts: inputs.accounts,
            accountSnapshots: inputs.accountSnapshots,
            transactions: inputs.transactions,
            currentAssets: currentAssets,
            currentLiabilities: currentLiabilities,
            currentNetWorth: currentNetWorth,
            referenceDate: referenceDate,
            range: range
        )
    }

    private func scheduleChartRebuild(referenceDate: Date = Date()) {
        chartRebuildTask?.cancel()
        if cachedChartPoints.isEmpty, cachedChartInputs != nil {
            chartRebuildTask = Task { @MainActor in
                await performChartRebuild(referenceDate: referenceDate)
            }
            return
        }
        chartRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performChartRebuild(referenceDate: referenceDate)
        }
    }

    private func performChartRebuild(referenceDate: Date = Date()) async {
        guard let inputs = cachedChartInputs else { return }
        let snapshots = snapshots
        let assets = currentAssets
        let liabilities = currentLiabilities
        let net = currentNetWorth

        let cache = await Task.detached(priority: .utility) {
            var built: [NetWorthTimeRange: [NetWorthChartPoint]] = [:]
            for range in NetWorthTimeRange.allCases {
                built[range] = NetWorthHistoryEngine.chartPoints(
                    snapshots: snapshots,
                    accounts: inputs.accounts,
                    accountSnapshots: inputs.accountSnapshots,
                    transactions: inputs.transactions,
                    currentAssets: assets,
                    currentLiabilities: liabilities,
                    currentNetWorth: net,
                    referenceDate: referenceDate,
                    range: range
                )
            }
            return built
        }.value

        cachedChartPoints = cache
    }

    func recordDailySnapshotIfNeeded(
        client: SupabaseClient,
        accounts: [Account],
        accountBalances: AccountBalanceStore
    ) async {
        let totals = NetWorthCalculator.totals(from: accounts)
        currentAssets = totals.assets
        currentLiabilities = totals.liabilities
        currentNetWorth = totals.net

        await accountBalances.recordTodaySnapshots(accounts: accounts, client: client)

        let today = FinanceDate.todayString()
        if let existing = snapshots.first(where: { $0.date == today }),
           existing.netWorth == totals.net,
           existing.totalAssets == totals.assets,
           existing.totalLiabilities == totals.liabilities {
            scheduleChartRebuild()
            return
        }
        await captureSnapshot(client: client, accounts: accounts, accountBalances: nil)
    }

    func captureSnapshot(
        client: SupabaseClient,
        accounts: [Account],
        accountBalances: AccountBalanceStore? = nil
    ) async {
        let totals = NetWorthCalculator.totals(from: accounts)
        let snapshot = NetWorthSnapshot(
            id: UUID(),
            date: FinanceDate.todayString(),
            totalAssets: totals.assets,
            totalLiabilities: totals.liabilities,
            netWorth: totals.net
        )
        do {
            let saved = try await SupabaseService.shared.saveNetWorthSnapshot(snapshot, client: client)
            snapshots.removeAll { $0.date == saved.date }
            snapshots.insert(saved, at: 0)
            currentAssets = totals.assets
            currentLiabilities = totals.liabilities
            currentNetWorth = totals.net
            if let inputs = cachedChartInputs {
                chartCacheKey = nil
                updateChartInputs(
                    accounts: inputs.accounts,
                    accountSnapshots: inputs.accountSnapshots,
                    transactions: inputs.transactions
                )
            } else {
                scheduleChartRebuild()
            }
            if let accountBalances {
                await accountBalances.recordTodaySnapshots(accounts: accounts, client: client)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct ChartInputs {
        let accounts: [Account]
        let accountSnapshots: [AccountBalanceSnapshot]
        let transactions: [Transaction]
    }

    private struct ChartCacheKey: Equatable {
        let accountSignature: String
        let snapshotSignature: String
        let netWorthSnapshotSignature: String
        let transactionCount: Int
    }

    private var cachedChartInputs: ChartInputs?
    private var chartCacheKey: ChartCacheKey?

    private func chartCacheKey(
        accounts: [Account],
        accountSnapshots: [AccountBalanceSnapshot],
        transactions: [Transaction]
    ) -> ChartCacheKey {
        ChartCacheKey(
            accountSignature: accounts
                .map { "\($0.id.uuidString)-\($0.currentBalance ?? 0)-\($0.type)" }
                .joined(separator: "|"),
            snapshotSignature: accountSnapshots
                .map { "\($0.accountId.uuidString)-\($0.date)-\($0.currentBalance ?? 0)" }
                .joined(separator: "|"),
            netWorthSnapshotSignature: snapshots
                .map { "\($0.date)-\($0.netWorth)" }
                .joined(separator: "|"),
            transactionCount: transactions.count
        )
    }

    private func updateChartInputs(
        accounts: [Account],
        accountSnapshots: [AccountBalanceSnapshot],
        transactions: [Transaction]
    ) {
        let key = chartCacheKey(
            accounts: accounts,
            accountSnapshots: accountSnapshots,
            transactions: transactions
        )
        guard key != chartCacheKey else { return }
        chartCacheKey = key
        cachedChartInputs = ChartInputs(
            accounts: accounts,
            accountSnapshots: accountSnapshots,
            transactions: transactions
        )
        scheduleChartRebuild()
    }
}
