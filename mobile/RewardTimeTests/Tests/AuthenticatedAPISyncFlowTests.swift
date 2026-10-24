import XCTest
@testable import ConnectJSONClient

final class AuthenticatedAPISyncFlowTests: XCTestCase {
    func testDoesNotRunAPISyncWhenSignedOut() async throws {
        var requestCount = 0

        try await AuthenticatedAPISyncFlow.run(isAuthenticated: false) {
            requestCount += 1
        }

        XCTAssertEqual(requestCount, 0)
    }

    func testRunsAPISyncWhenAuthenticated() async throws {
        var requestCount = 0

        try await AuthenticatedAPISyncFlow.run(isAuthenticated: true) {
            requestCount += 1
        }

        XCTAssertEqual(requestCount, 1)
    }
}
