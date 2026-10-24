import Foundation

protocol HomeRepository {
    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot
}

struct MockHomeRepository: HomeRepository {
    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot {
        MobileHomeSnapshot(
            sessionStatus: .working,
            rewardBalanceMinutes: 42,
            restrictionStatus: .restricted,
            lastSyncedAt: .now
        )
    }
}
