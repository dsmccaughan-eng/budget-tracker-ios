import XCTest
@testable import BudgetTracker

final class InvestmentModelsDecodingTests: XCTestCase {
    func testHoldingDecodesNumericStringsFromPostgREST() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "account_id": "550e8400-e29b-41d4-a716-446655440001",
          "security_id": null,
          "plaid_security_id": "sec_btc",
          "quantity": "0.125",
          "institution_price": "64000.50",
          "institution_value": "8000.06",
          "cost_basis": "1000",
          "iso_currency_code": "USD"
        }
        """.data(using: .utf8)!

        let holding = try JSONDecoder().decode(InvestmentHolding.self, from: json)
        XCTAssertEqual(holding.quantity, 0.125, accuracy: 0.0001)
        XCTAssertEqual(holding.institutionPrice ?? 0, 64000.50, accuracy: 0.01)
        XCTAssertEqual(holding.institutionValue ?? 0, 8000.06, accuracy: 0.01)
        XCTAssertEqual(holding.costBasis ?? 0, 1000, accuracy: 0.01)
    }

    func testTransactionDecodesAmountAndDateStrings() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440002",
          "account_id": "550e8400-e29b-41d4-a716-446655440001",
          "security_id": null,
          "plaid_investment_transaction_id": "inv_1",
          "plaid_account_id": "acc_1",
          "plaid_security_id": null,
          "name": "Buy AAPL",
          "type": "buy",
          "subtype": "buy",
          "date": "2026-08-01",
          "quantity": "2",
          "amount": "350.25",
          "price": "175.12",
          "fees": "0",
          "iso_currency_code": "USD"
        }
        """.data(using: .utf8)!

        let txn = try JSONDecoder().decode(InvestmentTransaction.self, from: json)
        XCTAssertEqual(txn.date, "2026-08-01")
        XCTAssertEqual(txn.amount, 350.25, accuracy: 0.01)
        XCTAssertEqual(txn.quantity ?? 0, 2, accuracy: 0.01)
    }
}
