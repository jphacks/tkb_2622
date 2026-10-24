import Foundation

struct MobileHomeSnapshot {
    let sessionStatus: SessionStatus
    let rewardBalanceMinutes: Int
    let restrictionStatus: RestrictionStatus
    let lastSyncedAt: Date

    static let workingSample = MobileHomeSnapshot(
        sessionStatus: .working,
        rewardBalanceMinutes: 42,
        restrictionStatus: .restricted,
        lastSyncedAt: .now
    )

    static let pausedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        rewardBalanceMinutes: 42,
        restrictionStatus: .restricted,
        lastSyncedAt: .now
    )

    static let releasedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        rewardBalanceMinutes: 32,
        restrictionStatus: .temporarilyReleased(endsAt: .now.addingTimeInterval(10 * 60)),
        lastSyncedAt: .now
    )

    static let noSessionSample = MobileHomeSnapshot(
        sessionStatus: .noSession,
        rewardBalanceMinutes: 0,
        restrictionStatus: .unrestricted,
        lastSyncedAt: .now
    )
}

enum SessionStatus {
    case noSession
    case working
    case paused
}

enum RestrictionStatus {
    case unrestricted
    case restricted
    case temporarilyReleased(endsAt: Date)
    case notConfirmed
}
