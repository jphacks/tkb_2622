import XCTest
@testable import ConnectJSONClient

final class HomeViewModelTests: XCTestCase {
    @MainActor
    func testRefreshFailureKeepsLastSnapshotAndExposesStaleDataWarning() async {
        let repository = SequentialHomeRepository(results: [
            .success(.noSessionSample),
            .failure(RepositoryFailure.offline),
        ])
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()
        let refreshSucceeded = await viewModel.refresh()
        XCTAssertFalse(refreshSucceeded)

        guard case .loaded(let snapshot) = viewModel.state else {
            return XCTFail("A transient refresh error should keep the last successful snapshot visible")
        }
        XCTAssertTrue(snapshot.isSampleData)
        XCTAssertEqual(viewModel.refreshError, "test network failure")
    }
}

private enum RepositoryFailure: LocalizedError {
    case offline

    var errorDescription: String? { "test network failure" }
}

private actor SequentialHomeRepository: HomeRepository {
    private var results: [Result<MobileHomeSnapshot, RepositoryFailure>]

    init(results: [Result<MobileHomeSnapshot, RepositoryFailure>]) {
        self.results = results
    }

    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot {
        guard !results.isEmpty else { throw RepositoryFailure.offline }
        return try results.removeFirst().get()
    }
}
