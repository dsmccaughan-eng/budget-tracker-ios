import Foundation

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
