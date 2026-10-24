import Foundation

struct MobileHomeSnapshot {
    let sessionStatus: SessionStatus
    let rewardBalanceMinutes: Int
    let restrictionStatus: RestrictionStatus
    let lastSyncedAt: Date
}

enum SessionStatus {
    case noSession
    case working
    case paused
}

enum RestrictionStatus {
    case restricted
    case temporarilyReleased(endsAt: Date)
    case notConfirmed
}
