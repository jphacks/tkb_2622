import Foundation
import XCTest
@testable import RewardTime

@MainActor
final class HistoryViewModelSimulatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HistoryErrorURLProtocol.handler = nil
    }

    override func tearDown() {
        HistoryErrorURLProtocol.handler = nil
        super.tearDown()
    }

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

    func testHistoryRepositoryErrorNamesFailedRPC() async {
        HistoryErrorURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            XCTAssertTrue(
                path.hasSuffix("/focus.v1.FocusService/ListSessions")
                    || path.hasSuffix("/reward.v1.RewardService/ListTransactions")
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":"internal","message":"request failed"}"#.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryErrorURLProtocol.self]
        let client = ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: HistoryTestTokenProvider()
        )
        let repository = ConfiguredHistoryRepository(client: client)

        do {
            _ = try await repository.fetchWorkHistory()
            XCTFail("Expected an API error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("focus.v1.FocusService/ListSessions"))
        }

        do {
            _ = try await repository.fetchRewardHistory()
            XCTFail("Expected a reward history API error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("reward.v1.RewardService/ListTransactions"))
        }
    }
}

private struct HistoryTestTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class HistoryErrorURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
