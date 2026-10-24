import XCTest
@testable import RewardTime

@MainActor
final class UsageGrantSyncCoordinatorSimulatorTests: XCTestCase {
    func testAutomaticUsageSyncFailureIsVisibleAndClearedAfterRetry() async {
        let coordinator = UsageGrantSyncCoordinator()

        await coordinator.synchronize {
            throw UsageSyncTestError.api("ReportUsage (internal)")
        }

        XCTAssertEqual(coordinator.errorMessage, "ReportUsage (internal)")

        await coordinator.synchronize {}

        XCTAssertNil(coordinator.errorMessage)
    }
}

private enum UsageSyncTestError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        }
    }
}
