import Foundation
import Supabase

@MainActor
final class AccountBalanceStore: ObservableObject {
    @Published private(set) var snapshots: [AccountBalanceSnapshot] = []
    @Published var errorMessage: String?

    func reload(client: SupabaseClient) async {
        errorMessage = nil
        let since = SupabaseService.transactionHistorySinceDate()
        do {
            snapshots = try await SupabaseService.shared.fetchAccountBalanceSnapshots(
                client: client,
                since: since
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordTodaySnapshots(accounts: [Account], client: SupabaseClient) async {
        errorMessage = nil
        let today = Self.todayString()
        let accountIds = Set(accounts.map(\.id))
        let covered = Set(
            snapshots
                .filter { $0.date == today && accountIds.contains($0.accountId) }
                .map(\.accountId)
        )
        let missing = accounts.filter { !covered.contains($0.id) }
        guard !missing.isEmpty else { return }

        let rows = missing.map { account in
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: account.id,
                date: today,
                currentBalance: account.currentBalance,
                availableBalance: account.availableBalance
            )
        }

        do {
            try await SupabaseService.shared.upsertAccountBalanceSnapshots(rows, client: client)
            for row in rows {
                snapshots.removeAll { $0.accountId == row.accountId && $0.date == row.date }
                snapshots.insert(row, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func todayString(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
