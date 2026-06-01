import Foundation
import Supabase

@MainActor
final class GoalsStore: ObservableObject {
    @Published private(set) var savingsGoals: [SavingsGoal] = []
    @Published private(set) var debtAccounts: [DebtAccount] = []
    @Published var debtStrategy: DebtPayoffStrategy = .avalanche
    @Published var extraDebtPayment: Double = 0
    @Published private(set) var payoffSteps: [DebtPayoffStep] = []
    @Published private(set) var suggestedEmergencyFund: Double = 0
    @Published var errorMessage: String?

    private let debtKey = "budgettracker.debt.accounts"

    func reload(client: SupabaseClient, transactions: [Transaction]) async {
        errorMessage = nil
        loadDebtAccounts()
        suggestedEmergencyFund = SavingsGoalMath.suggestedEmergencyFund(transactions: transactions)
        recomputePayoffPlan()
        do {
            savingsGoals = try await SupabaseService.shared.fetchSavingsGoals(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSavingsGoal(_ draft: SavingsGoalDraft, client: SupabaseClient) async {
        errorMessage = nil
        do {
            let goal = SavingsGoal(
                id: UUID(),
                name: draft.name,
                targetAmount: draft.targetAmount,
                currentAmount: draft.currentAmount,
                monthlyContribution: draft.monthlyContribution,
                targetDate: draft.targetDate,
                linkedAccountId: draft.linkedAccountId,
                emoji: draft.emoji
            )
            let saved = try await SupabaseService.shared.saveSavingsGoal(goal, client: client)
            savingsGoals.insert(saved, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSavingsGoal(_ goal: SavingsGoal, client: SupabaseClient) async {
        do {
            try await SupabaseService.shared.deleteSavingsGoal(id: goal.id, client: client)
            savingsGoals.removeAll { $0.id == goal.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addDebtAccount(_ draft: DebtAccountDraft) {
        let account = DebtAccount(
            id: UUID(),
            name: draft.name,
            balance: draft.balance,
            apr: draft.apr,
            minimumPayment: draft.minimumPayment
        )
        debtAccounts.append(account)
        persistDebtAccounts()
        recomputePayoffPlan()
    }

    func removeDebtAccount(_ account: DebtAccount) {
        debtAccounts.removeAll { $0.id == account.id }
        persistDebtAccounts()
        recomputePayoffPlan()
    }

    func recomputePayoffPlan() {
        payoffSteps = DebtPayoffEngine.payoffPlan(
            accounts: debtAccounts,
            extraMonthlyPayment: extraDebtPayment,
            strategy: debtStrategy
        )
    }

    private func loadDebtAccounts() {
        guard let data = UserDefaults.standard.data(forKey: debtKey),
              let decoded = try? JSONDecoder().decode([DebtAccount].self, from: data) else { return }
        debtAccounts = decoded
    }

    private func persistDebtAccounts() {
        guard let data = try? JSONEncoder().encode(debtAccounts) else { return }
        UserDefaults.standard.set(data, forKey: debtKey)
    }
}

struct SavingsGoalDraft {
    var name = "Emergency Fund"
    var targetAmount = 1000.0
    var currentAmount = 0.0
    var monthlyContribution = 100.0
    var targetDate: String?
    var linkedAccountId: UUID?
    var emoji = "🎯"
}

struct DebtAccountDraft {
    var name = ""
    var balance = 0.0
    var apr = 0.0
    var minimumPayment = 0.0
}

@MainActor
final class NetWorthStore: ObservableObject {
    @Published private(set) var snapshots: [NetWorthSnapshot] = []
    @Published private(set) var currentAssets: Double = 0
    @Published private(set) var currentLiabilities: Double = 0
    @Published private(set) var currentNetWorth: Double = 0
    @Published var errorMessage: String?

    func reload(client: SupabaseClient, accounts: [Account]) async {
        errorMessage = nil
        let totals = NetWorthCalculator.totals(from: accounts)
        currentAssets = totals.assets
        currentLiabilities = totals.liabilities
        currentNetWorth = totals.net
        do {
            snapshots = try await SupabaseService.shared.fetchNetWorthSnapshots(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureSnapshot(
        client: SupabaseClient,
        accounts: [Account],
        accountBalances: AccountBalanceStore? = nil
    ) async {
        let totals = NetWorthCalculator.totals(from: accounts)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let snapshot = NetWorthSnapshot(
            id: UUID(),
            date: formatter.string(from: Date()),
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
            if let accountBalances {
                await accountBalances.recordTodaySnapshots(accounts: accounts, client: client)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
