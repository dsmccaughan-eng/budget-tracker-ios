import XCTest
@testable import BudgetTracker

@MainActor
final class InvestmentStoreBalanceTests: XCTestCase {
    func testPreferredBalanceUsesHoldingsWhenHigherThanPlaid() {
        let accountId = UUID()
        let store = InvestmentStore()
        store.replaceHoldingsForTests([
            InvestmentHolding(
                id: UUID(),
                accountId: accountId,
                securityId: nil,
                plaidSecurityId: "a",
                quantity: 10,
                institutionPrice: 100,
                institutionValue: 50_000,
                costBasis: 40_000,
                isoCurrencyCode: "USD"
            ),
            InvestmentHolding(
                id: UUID(),
                accountId: accountId,
                securityId: nil,
                plaidSecurityId: "b",
                quantity: 1,
                institutionPrice: 1000,
                institutionValue: 12_000,
                costBasis: 10_000,
                isoCurrencyCode: "USD"
            ),
        ])
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "Principal",
            officialName: nil,
            type: "investment",
            subtype: "401k",
            mask: nil,
            currentBalance: 40_000,
            availableBalance: nil
        )
        XCTAssertEqual(store.preferredBalance(for: account) ?? 0, 62_000, accuracy: 0.01)
    }

    func testPreferredBalanceUsesHoldingsEvenWhenLowerThanPlaid() {
        let accountId = UUID()
        let store = InvestmentStore()
        store.replaceHoldingsForTests([
            InvestmentHolding(
                id: UUID(),
                accountId: accountId,
                securityId: nil,
                plaidSecurityId: "a",
                quantity: 1,
                institutionPrice: 1_000,
                institutionValue: 55_000,
                costBasis: 50_000,
                isoCurrencyCode: "USD"
            ),
        ])
        let account = Account(
            id: accountId,
            plaidItemId: "item",
            plaidAccountId: "acc",
            name: "Principal",
            officialName: nil,
            type: "investment",
            subtype: "401k",
            mask: nil,
            currentBalance: 90_000,
            availableBalance: nil
        )
        XCTAssertEqual(store.preferredBalance(for: account) ?? 0, 55_000, accuracy: 0.01)
    }
}
