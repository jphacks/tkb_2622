import Foundation
import XCTest
@testable import RewardTime

@MainActor
final class GroupFocusWidgetSyncSimulatorTests: XCTestCase {
    private let members = [
        MobileGroupFocusMember(displayName: "友達", avatarID: "cat", startedAt: Date(timeIntervalSince1970: 100))
    ]

    func testSynchronizeSavesFocusedMembersWithoutRequiringForegroundState() async {
        var saved: [MobileGroupFocusMember]?
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { self.members },
            currentUserID: { "user-1" },
            save: { saved = $0 },
            clear: { XCTFail("A successful sync must not clear the cache") },
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertTrue(success)
        XCTAssertEqual(saved, members)
    }

    func testEmptyResponseReplacesPreviouslyFocusedMembers() async {
        var saved = members
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { [] },
            currentUserID: { "user-1" },
            save: { saved = $0 },
            clear: {},
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertTrue(success)
        XCTAssertTrue(saved.isEmpty)
    }

    func testFailedFetchPreservesLastSuccessfulSnapshot() async {
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { throw URLError(.notConnectedToInternet) },
            currentUserID: { "user-1" },
            save: { _ in XCTFail("A failure must not replace the last successful snapshot") },
            clear: { XCTFail("A network failure must not clear the cache") },
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertFalse(success)
    }

    func testMissingAccountClearsCacheWithoutFetching() async {
        var didClear = false
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { XCTFail("A signed-out app must not fetch members"); return [] },
            currentUserID: { nil },
            save: { _ in XCTFail("A signed-out app must not save members") },
            clear: { didClear = true },
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertFalse(success)
        XCTAssertTrue(didClear)
    }

    func testAccountChangeDuringFetchDiscardsResponse() async {
        var userID = "user-1"
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { userID = "user-2"; return self.members },
            currentUserID: { userID },
            save: { _ in XCTFail("A response for the previous account must be discarded") },
            clear: {},
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertFalse(success)
    }

    func testSignOutDuringFetchDiscardsResponse() async {
        var userID: String? = "user-1"
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { userID = nil; return self.members },
            currentUserID: { userID },
            save: { _ in XCTFail("A late response must not restore signed-out data") },
            clear: {},
            isShowingLocalPreview: { false }
        )

        let success = await coordinator.synchronize()

        XCTAssertFalse(success)
    }

    func testExpirationCancellationDiscardsEvenANonCooperativeFetchResponse() async {
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: {
                withUnsafeCurrentTask { $0?.cancel() }
                return self.members
            },
            currentUserID: { "user-1" },
            save: { _ in XCTFail("An expired background task must not save its response") },
            clear: {},
            isShowingLocalPreview: { false }
        )

        let work = Task { await coordinator.synchronize() }
        let success = await work.value

        XCTAssertFalse(success)
    }

    func testLocalPreviewSkipsNetworkAndKeepsSample() async {
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { XCTFail("Local preview must not call the API"); return [] },
            currentUserID: { nil },
            save: { _ in XCTFail("Local preview must keep the sample") },
            clear: { XCTFail("Local preview must keep the sample") },
            isShowingLocalPreview: { true }
        )

        let success = await coordinator.synchronize()

        XCTAssertTrue(success)
    }

    func testPreviewEnabledDuringFetchIsNotOverwritten() async {
        var preview = false
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { preview = true; return self.members },
            currentUserID: { "user-1" },
            save: { _ in XCTFail("An in-flight response must not overwrite preview data") },
            clear: {},
            isShowingLocalPreview: { preview }
        )

        let success = await coordinator.synchronize()

        XCTAssertFalse(success)
    }

    func testInactiveSceneDoesNotStartForegroundPolling() async {
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: { XCTFail("Inactive scenes must not poll"); return [] },
            currentUserID: { "user-1" },
            save: { _ in XCTFail("Inactive scenes must not poll") },
            clear: { XCTFail("An authenticated inactive scene must keep its cache") },
            isShowingLocalPreview: { false }
        )

        await coordinator.run(isAuthenticated: true, isActive: false)
    }

    func testOlderForegroundResponseCannotOverwriteANewerBackgroundSync() async throws {
        let firstFetchStarted = expectation(description: "First request started")
        var firstResponse: CheckedContinuation<[MobileGroupFocusMember], Never>?
        var fetchCount = 0
        var saved = [[MobileGroupFocusMember]]()
        let coordinator = GroupFocusWidgetSyncCoordinator(
            fetchMembers: {
                fetchCount += 1
                if fetchCount == 1 {
                    return await withCheckedContinuation {
                        firstResponse = $0
                        firstFetchStarted.fulfill()
                    }
                }
                return []
            },
            currentUserID: { "user-1" },
            save: { saved.append($0) },
            clear: {},
            isShowingLocalPreview: { false }
        )

        let first = Task { await coordinator.synchronize() }
        await fulfillment(of: [firstFetchStarted], timeout: 2)
        let latestSucceeded = await coordinator.synchronize()
        let response = try XCTUnwrap(firstResponse)
        response.resume(returning: members)
        let firstSucceeded = await first.value

        XCTAssertTrue(latestSucceeded)
        XCTAssertFalse(firstSucceeded)
        XCTAssertEqual(saved, [[]])
    }

    func testAppPermitsTheRegisteredBackgroundRefresh() throws {
        let identifiers = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])

        XCTAssertTrue(identifiers.contains(GroupFocusWidgetBackgroundRefresh.taskIdentifier))
        XCTAssertTrue(modes.contains("fetch"))
    }
}
