import XCTest
@testable import ConnectJSONClient

final class AuthenticatedAPISyncFlowTests: XCTestCase {
    func testDoesNotRunAPISyncWhenSignedOut() async throws {
        var requestCount = 0

        let didRun = try await AuthenticatedAPISyncFlow.run(isAuthenticated: false) {
            requestCount += 1
        }

        XCTAssertFalse(didRun)
        XCTAssertEqual(requestCount, 0)
    }

    func testRunsAPISyncWhenAuthenticated() async throws {
        var requestCount = 0

        let didRun = try await AuthenticatedAPISyncFlow.run(isAuthenticated: true) {
            requestCount += 1
        }

        XCTAssertTrue(didRun)
        XCTAssertEqual(requestCount, 1)
    }
}
