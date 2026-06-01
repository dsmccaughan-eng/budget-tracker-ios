import Foundation

struct DebtAccount: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var balance: Double
    var apr: Double
    var minimumPayment: Double
}

struct DebtPayoffStep: Equatable, Identifiable {
    var id: String { "\(monthIndex)-\(accountName)" }
    let monthIndex: Int
    let accountName: String
    let payment: Double
    let remainingBalance: Double
}

enum DebtPayoffStrategy: String, CaseIterable, Identifiable {
    case avalanche
    case snowball

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avalanche: return "Avalanche (highest APR)"
        case .snowball: return "Snowball (smallest balance)"
        }
    }
}

enum DebtPayoffEngine {
    static func monthlyInterest(balance: Double, apr: Double) -> Double {
        guard balance > 0, apr > 0 else { return 0 }
        return balance * (apr / 100.0) / 12.0
    }

    static func payoffPlan(
        accounts: [DebtAccount],
        extraMonthlyPayment: Double,
        strategy: DebtPayoffStrategy,
        maxMonths: Int = 360
    ) -> [DebtPayoffStep] {
        guard !accounts.isEmpty else { return [] }

        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, max($0.balance, 0)) })
        var steps: [DebtPayoffStep] = []
        var month = 1

        while month <= maxMonths, balances.values.contains(where: { $0 > 0.01 }) {
            var interestByAccount: [UUID: Double] = [:]
            for account in accounts {
                let balance = balances[account.id, default: 0]
                interestByAccount[account.id] = monthlyInterest(balance: balance, apr: account.apr)
                balances[account.id] = balance + interestByAccount[account.id, default: 0]
            }

            var paymentBudget = accounts.reduce(0) { $0 + max($1.minimumPayment, 0) } + max(extraMonthlyPayment, 0)
            let active = accounts.filter { balances[$0.id, default: 0] > 0.01 }

            for account in active {
                let pay = min(balances[account.id, default: 0], account.minimumPayment)
                balances[account.id, default: 0] = max(balances[account.id, default: 0] - pay, 0)
                paymentBudget -= pay
                steps.append(DebtPayoffStep(
                    monthIndex: month,
                    accountName: account.name,
                    payment: pay,
                    remainingBalance: balances[account.id, default: 0]
                ))
            }

            let target = prioritizedAccount(active: active, balances: balances, strategy: strategy)
            if let target, paymentBudget > 0 {
                let pay = min(balances[target.id, default: 0], paymentBudget)
                balances[target.id, default: 0] = max(balances[target.id, default: 0] - pay, 0)
                paymentBudget -= pay
                steps.append(DebtPayoffStep(
                    monthIndex: month,
                    accountName: target.name,
                    payment: pay,
                    remainingBalance: balances[target.id, default: 0]
                ))
            }

            month += 1
        }

        return steps
    }

    static func payoffMonthCount(steps: [DebtPayoffStep]) -> Int {
        steps.last?.monthIndex ?? 0
    }

    private static func prioritizedAccount(
        active: [DebtAccount],
        balances: [UUID: Double],
        strategy: DebtPayoffStrategy
    ) -> DebtAccount? {
        switch strategy {
        case .avalanche:
            return active.max { lhs, rhs in
                if lhs.apr == rhs.apr {
                    return balances[lhs.id, default: 0] < balances[rhs.id, default: 0]
                }
                return lhs.apr < rhs.apr
            }
        case .snowball:
            return active.min { balances[$0.id, default: 0] < balances[$1.id, default: 0] }
        }
    }
}

enum NetWorthCalculator {
    static func totals(from accounts: [Account]) -> (assets: Double, liabilities: Double, net: Double) {
        var assets = 0.0
        var liabilities = 0.0
        for account in accounts {
            let split = contribution(accountType: account.type, balance: account.currentBalance ?? 0)
            assets += split.assets
            liabilities += split.liabilities
        }
        return (assets, liabilities, assets - liabilities)
    }

    static func contribution(accountType: String, balance: Double) -> (assets: Double, liabilities: Double) {
        switch accountType.lowercased() {
        case "credit", "loan":
            return (0, abs(balance))
        case "investment", "depository", "brokerage":
            return (max(balance, 0), 0)
        default:
            if balance >= 0 { return (balance, 0) }
            return (0, abs(balance))
        }
    }
}

enum SavingsGoalMath {
    static func suggestedEmergencyFund(transactions: [Transaction], months: Int = 3) -> Double {
        let essentials: Set<String> = [
            "Housing & Utilities", "Groceries", "Transport", "Health & Wellness", "Subscriptions"
        ]
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return 0 }

        let recent = transactions.filter { txn in
            guard essentials.contains(txn.category), let date = parseDate(txn.date) else { return false }
            return date >= start
        }
        let total = recent.reduce(0) { $0 + abs($1.amount) }
        let monthlyAverage = total / 3.0
        return monthlyAverage * Double(months)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func projectedCompletionDate(
        current: Double,
        target: Double,
        monthlyContribution: Double
    ) -> Date? {
        guard monthlyContribution > 0, target > current else { return nil }
        let months = ceil((target - current) / monthlyContribution)
        return Calendar.current.date(byAdding: .month, value: Int(months), to: Date())
    }
}
