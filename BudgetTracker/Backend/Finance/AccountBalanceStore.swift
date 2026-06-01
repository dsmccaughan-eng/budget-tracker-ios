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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let rows = accounts.map { account in
            AccountBalanceSnapshot(
                id: UUID(),
                accountId: account.id,
                date: today,
                currentBalance: account.currentBalance,
                availableBalance: account.availableBalance
            )
        }
        guard !rows.isEmpty else { return }

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
}
