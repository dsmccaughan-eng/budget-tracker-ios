import XCTest
@testable import BudgetTracker

final class PINHasherTests: XCTestCase {
    func testValidPINFormat() {
        XCTAssertTrue(PINHasher.isValidPINFormat("123456"))
        XCTAssertFalse(PINHasher.isValidPINFormat("1234"))
        XCTAssertFalse(PINHasher.isValidPINFormat("1234567"))
        XCTAssertFalse(PINHasher.isValidPINFormat("12ab56"))
    }

    func testHashVerifyRoundTrip() throws {
        let salt = try PINHasher.generateSalt()
        let hash = try PINHasher.hash(pin: "654321", salt: salt)
        XCTAssertTrue(PINHasher.verify(pin: "654321", salt: salt, expectedHash: hash))
        XCTAssertFalse(PINHasher.verify(pin: "000000", salt: salt, expectedHash: hash))
    }

    func testConstantTimeEqual() {
        let a = Data(repeating: 1, count: 32)
        let b = Data(repeating: 1, count: 32)
        let c = Data(repeating: 2, count: 32)
        XCTAssertTrue(PINHasher.constantTimeEqual(a, b))
        XCTAssertFalse(PINHasher.constantTimeEqual(a, c))
        XCTAssertFalse(PINHasher.constantTimeEqual(a, Data()))
    }
}
