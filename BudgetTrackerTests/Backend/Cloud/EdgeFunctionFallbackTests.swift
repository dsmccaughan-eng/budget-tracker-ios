import XCTest
@testable import BudgetTracker

final class EdgeFunctionFallbackTests: XCTestCase {
    func testDetects404InFunctionErrorMessage() {
        struct SampleError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
        let error = SampleError(message: "Edge Function returned a non-2xx status code: 404")
        XCTAssertTrue(EdgeFunctionFallback.isMissingFunction(error))
    }

    func testIgnoresUnrelatedErrors() {
        struct SampleError: LocalizedError {
            var errorDescription: String? { "Rate limit exceeded" }
        }
        XCTAssertFalse(EdgeFunctionFallback.isMissingFunction(SampleError()))
    }
}
