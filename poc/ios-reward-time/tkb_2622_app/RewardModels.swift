import Foundation

struct RewardSnapshot: Codable, Equatable, Sendable {
    var balanceMinutes: Int
    var unlockEndsAt: Date?

    static let demo = RewardSnapshot(balanceMinutes: 60, unlockEndsAt: nil)

    func unlockStatus(at date: Date) -> UnlockStatus {
        guard let unlockEndsAt else { return .locked }
        if unlockEndsAt > date {
            return .unlocked(endsAt: unlockEndsAt)
        }
        return .expired(endsAt: unlockEndsAt)
    }
}

enum UnlockStatus: Equatable, Sendable {
    case locked
    case unlocked(endsAt: Date)
    case expired(endsAt: Date)
}

enum RewardRepositoryError: LocalizedError {
    case invalidDuration
    case insufficientBalance

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "利用時間は1分以上で入力してください。"
        case .insufficientBalance:
            return "報酬残高が不足しています。"
        }
    }
}
