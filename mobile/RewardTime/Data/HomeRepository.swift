import Foundation

protocol HomeRepository {
    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot
}

struct MockHomeRepository: HomeRepository {
    private let snapshot: MobileHomeSnapshot

    init(snapshot: MobileHomeSnapshot = .workingSample) {
        self.snapshot = snapshot
    }

    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot {
        snapshot
    }
}
