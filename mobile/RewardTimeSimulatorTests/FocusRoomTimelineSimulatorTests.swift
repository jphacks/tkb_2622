import Foundation
import XCTest

final class FocusRoomTimelineSimulatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshSnapshotHasMovementEntriesAndAnExplicitExpirationEntry() {
        let dates = FocusRoomTimeline.dates(now: now, updatedAt: now, isLocalPreview: false)

        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [0, 300, 600, 720])
        XCTAssertEqual(dates.map { FocusRoomTimeline.movementPhase(at: $0) }, [0, 1, 2, 0])
    }

    func testCachedSnapshotExpiresRelativeToItsLastSuccessfulFetch() {
        let dates = FocusRoomTimeline.dates(
            now: now, updatedAt: now.addingTimeInterval(-8 * 60), isLocalPreview: false
        )

        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [0, 240])
    }

    func testExpiredAndMissingSnapshotsHaveNoFutureMovementEntries() {
        XCTAssertEqual(FocusRoomTimeline.dates(now: now, updatedAt: nil, isLocalPreview: false), [now])
        XCTAssertEqual(FocusRoomTimeline.dates(
            now: now, updatedAt: now.addingTimeInterval(-720), isLocalPreview: false
        ), [now])
    }

    func testConsecutiveAppReloadsAdvanceTheMovementPhase() {
        let phases = (0..<4).map {
            FocusRoomTimeline.movementPhase(at: now.addingTimeInterval(TimeInterval($0 * 60)))
        }

        XCTAssertEqual(phases, [0, 1, 2, 3])
    }

    func testLocalPreviewContinuesEvenIfItsFixtureIsOld() {
        let dates = FocusRoomTimeline.dates(
            now: now, updatedAt: now.addingTimeInterval(-3600), isLocalPreview: true
        )

        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [0, 300, 600])
    }
}
