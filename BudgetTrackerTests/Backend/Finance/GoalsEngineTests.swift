import XCTest
@testable import BudgetTracker

final class DebtPayoffEngineTests: XCTestCase {
    func testAvalanchePrioritizesHighApr() {
        let accounts = [
            DebtAccount(id: UUID(), name: "Card A", balance: 1000, apr: 24, minimumPayment: 50),
            DebtAccount(id: UUID(), name: "Card B", balance: 500, apr: 12, minimumPayment: 25)
        ]
        let steps = DebtPayoffEngine.payoffPlan(
            accounts: accounts,
            extraMonthlyPayment: 100,
            strategy: .avalanche,
            maxMonths: 6
        )
        XCTAssertFalse(steps.isEmpty)
        XCTAssertGreaterThan(DebtPayoffEngine.payoffMonthCount(steps: steps), 0)
    }

    func testSnowballProducesSteps() {
        let accounts = [
            DebtAccount(id: UUID(), name: "Small", balance: 200, apr: 10, minimumPayment: 25),
            DebtAccount(id: UUID(), name: "Large", balance: 2000, apr: 18, minimumPayment: 50)
        ]
        let steps = DebtPayoffEngine.payoffPlan(
            accounts: accounts,
            extraMonthlyPayment: 50,
            strategy: .snowball,
            maxMonths: 12
        )
        XCTAssertFalse(steps.isEmpty)
    }
}

final class CashFlowEngineTests: XCTestCase {
    func testHorizonTotalsPrefixDays() {
        let days = [
            CashFlowDay(date: "2026-05-01", inflow: 100, outflow: 40),
            CashFlowDay(date: "2026-05-02", inflow: 0, outflow: 20)
        ]
        let totals = CashFlowEngine.horizonTotals(days: days, first: 2)
        XCTAssertEqual(totals.inflow, 100, accuracy: 0.01)
        XCTAssertEqual(totals.outflow, 60, accuracy: 0.01)
        XCTAssertEqual(totals.net, 40, accuracy: 0.01)
    }
}

final class SubscriptionAuditEngineTests: XCTestCase {
    func testDetectsSubscriptionMerchants() {
        let txns = [
            Transaction(id: UUID(), accountId: UUID(), plaidTransactionId: "1", amount: 15.99, date: "2026-05-01", merchantName: "Netflix", name: "Netflix", category: "Subscriptions", subcategory: nil, pending: false, isManual: false, splitItems: nil),
            Transaction(id: UUID(), accountId: UUID(), plaidTransactionId: "2", amount: 15.99, date: "2026-04-01", merchantName: "Netflix", name: "Netflix", category: "Subscriptions", subcategory: nil, pending: false, isManual: false, splitItems: nil)
        ]
        let charges = SubscriptionAuditEngine.recurringCharges(transactions: txns, lookbackDays: 365)
        XCTAssertEqual(charges.first?.merchant.lowercased(), "netflix")
        XCTAssertGreaterThan(charges.first?.monthlyAmount ?? 0, 0)
    }
}

final class BudgetAlertEngineTests: XCTestCase {
    func testAlertWhenOverThreshold() {
        let row = BudgetProgress(
            category: "Groceries",
            monthlyLimit: 100,
            spent: 85,
            projectedSpend: 120,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertEqual(alerts.count, 1)
    }

    func testSkipsFixedBudgetAtThreshold() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBillCategoryAtThreshold() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(
            progress: [row],
            threshold: 0.8,
            fixedBillCategories: ["Housing & Utilities"]
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBillTransactionCategoryViaTransactionsParameter() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 1_900,
            projectedSpend: 2_000,
            isFixed: false,
            isRollover: false,
            color: "#000000"
        )
        let rent = Transaction(
            id: UUID(),
            accountId: UUID(),
            plaidTransactionId: UUID().uuidString,
            amount: 1_800,
            date: "2026-06-01",
            merchantName: "Landlord",
            name: "Landlord",
            category: "Housing & Utilities",
            subcategory: nil,
            pending: false,
            isManual: false,
            splitItems: nil,
            isFixedBill: true
        )
        let alerts = BudgetAlertEngine.alerts(
            progress: [row],
            transactions: [rent],
            threshold: 0.8
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSkipsFixedBudgetWhenOverBudget() {
        let row = BudgetProgress(
            category: "Housing & Utilities",
            monthlyLimit: 2_000,
            spent: 2_100,
            projectedSpend: 2_100,
            isFixed: true,
            isRollover: false,
            color: "#000000"
        )
        let alerts = BudgetAlertEngine.alerts(progress: [row], threshold: 0.8)
        XCTAssertTrue(alerts.isEmpty)
    }
}
