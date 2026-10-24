import Foundation
import XCTest
@testable import RewardTime

@MainActor
final class HistoryViewModelSimulatorTests: XCTestCase {
    func testReloadFailureKeepsBothHistoryListsAndShowsConnectError() async {
        let repository = SimulatorHistoryRepository()
        let model = HistoryViewModel(repository: repository)

        await model.load()
        XCTAssertEqual(model.workItems.map(\.id), ["session-1"])
        XCTAssertEqual(model.rewardItems.map(\.id), ["transaction-1"])

        await repository.failRequests()
        await model.load()

        XCTAssertEqual(model.workItems.map(\.id), ["session-1"])
        XCTAssertEqual(model.rewardItems.map(\.id), ["transaction-1"])
        XCTAssertTrue(model.isShowingStaleSnapshot)
        XCTAssertTrue(model.errorMessage?.contains("(internal)") == true)
    }

    func testLoadMoreFailureKeepsCurrentItemsAndPageToken() async {
        let repository = SimulatorHistoryRepository()
        let model = HistoryViewModel(repository: repository)
        await model.load()
        await repository.failRequests()

        await model.loadMore()

        XCTAssertEqual(model.workItems.map(\.id), ["session-1"])
        XCTAssertEqual(model.nextWorkPageToken, "work-page-2")
        XCTAssertTrue(model.errorMessage?.contains("(internal)") == true)
    }
}

private actor SimulatorHistoryRepository: HistoryRepository {
    private var shouldFail = false

    func failRequests() { shouldFail = true }

    func fetchWorkHistory(pageToken: String) async throws -> HistoryPage<WorkHistoryItem> {
        if shouldFail { throw ConnectJSONClient.ClientError.connect(code: "internal") }
        if pageToken.isEmpty {
            return HistoryPage(items: [workItem()], nextPageToken: "work-page-2")
        }
        return HistoryPage(items: [workItem(id: "session-2")], nextPageToken: "")
    }

    func fetchRewardHistory(pageToken: String) async throws -> HistoryPage<RewardHistoryItem> {
        if shouldFail { throw ConnectJSONClient.ClientError.connect(code: "internal") }
        return HistoryPage(items: [rewardItem()], nextPageToken: "reward-page-2")
    }

    private func workItem(id: String = "session-1") -> WorkHistoryItem {
        WorkHistoryItem(
            id: id,
            taskName: "Task",
            status: "SESSION_STATUS_COMPLETED",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            activeSeconds: 60,
            workSeconds: 60,
            earnedSeconds: 0,
            spentSeconds: 0,
            discardedSeconds: 0
        )
    }

    private func rewardItem() -> RewardHistoryItem {
        RewardHistoryItem(
            id: "transaction-1",
            sessionID: "session-1",
            type: "TRANSACTION_TYPE_EARNED",
            amountSeconds: 60,
            balanceAfterSeconds: 60,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
