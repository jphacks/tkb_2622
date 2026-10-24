import Foundation

@MainActor
protocol RewardRepository {
    func load() async throws -> RewardSnapshot
    func redeem(minutes: Int, now: Date) async throws -> RewardSnapshot
}

@MainActor
final class UserDefaultsRewardRepository: RewardRepository {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "rewardSnapshot"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() async throws -> RewardSnapshot {
        guard let data = defaults.data(forKey: storageKey) else {
            let initialSnapshot = RewardSnapshot.demo
            try save(initialSnapshot)
            return initialSnapshot
        }
        return try decoder.decode(RewardSnapshot.self, from: data)
    }

    func redeem(minutes: Int, now: Date) async throws -> RewardSnapshot {
        guard minutes > 0 else { throw RewardRepositoryError.invalidDuration }

        var snapshot = try await load()
        guard minutes <= snapshot.balanceMinutes else {
            throw RewardRepositoryError.insufficientBalance
        }

        snapshot.balanceMinutes -= minutes
        let unlockStartsAt = max(now, snapshot.unlockEndsAt ?? now)
        snapshot.unlockEndsAt = unlockStartsAt.addingTimeInterval(TimeInterval(minutes * 60))
        try save(snapshot)
        return snapshot
    }

    private func save(_ snapshot: RewardSnapshot) throws {
        defaults.set(try encoder.encode(snapshot), forKey: storageKey)
    }
}

@MainActor
final class InMemoryRewardRepository: RewardRepository {
    private var snapshot = RewardSnapshot.demo

    func load() async throws -> RewardSnapshot {
        snapshot
    }

    func redeem(minutes: Int, now: Date) async throws -> RewardSnapshot {
        guard minutes > 0 else { throw RewardRepositoryError.invalidDuration }
        guard minutes <= snapshot.balanceMinutes else {
            throw RewardRepositoryError.insufficientBalance
        }

        snapshot.balanceMinutes -= minutes
        let unlockStartsAt = max(now, snapshot.unlockEndsAt ?? now)
        snapshot.unlockEndsAt = unlockStartsAt.addingTimeInterval(TimeInterval(minutes * 60))
        return snapshot
    }
}
