import XCTest
@testable import RewardTime

@MainActor
final class MobileAPISyncCoordinatorSimulatorTests: XCTestCase {
    func testUsageFailureIsVisibleAndHomeRefreshStillRuns() async {
        let coordinator = MobileAPISyncCoordinator()
        var didRefreshHome = false

        await coordinator.synchronize(usage: {
            throw APISyncTestError.api("ReportUsage (internal)")
        }, refreshHome: {
            didRefreshHome = true
        })

        XCTAssertTrue(didRefreshHome)
        XCTAssertEqual(coordinator.errorMessage, "ReportUsage (internal)")

        await coordinator.synchronize(usage: {}, refreshHome: {})

        XCTAssertNil(coordinator.errorMessage)
    }

    func testHomeAPIErrorIsVisibleWhenUsageSyncSucceeds() async {
        let coordinator = MobileAPISyncCoordinator()

        await coordinator.synchronize(usage: {}, refreshHome: {
            throw APISyncTestError.api("GetCurrentSession (unavailable)")
        })

        XCTAssertEqual(coordinator.errorMessage, "GetCurrentSession (unavailable)")
    }
}

private enum APISyncTestError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        }
    }
}
