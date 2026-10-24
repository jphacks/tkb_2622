import Foundation

struct MobileHomeSnapshot {
    let sessionStatus: SessionStatus
    let elapsedWorkMinutes: Int?
    let minimumWorkMinutes: Int?
    let rewardBalanceMinutes: Int
    let restrictionStatus: RestrictionStatus
    let restrictedApps: [String]
    let lastSyncedAt: Date

    static let workingSample = MobileHomeSnapshot(
        sessionStatus: .working,
        elapsedWorkMinutes: 48,
        minimumWorkMinutes: 60,
        rewardBalanceMinutes: 32,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        lastSyncedAt: .now
    )

    static let pausedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedWorkMinutes: 48,
        minimumWorkMinutes: 60,
        rewardBalanceMinutes: 42,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        lastSyncedAt: .now
    )

    static let releasedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedWorkMinutes: 48,
        minimumWorkMinutes: 60,
        rewardBalanceMinutes: 32,
        restrictionStatus: .temporarilyReleased(endsAt: .now.addingTimeInterval(10 * 60)),
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        lastSyncedAt: .now
    )

    static let noSessionSample = MobileHomeSnapshot(
        sessionStatus: .noSession,
        elapsedWorkMinutes: nil,
        minimumWorkMinutes: nil,
        rewardBalanceMinutes: 0,
        restrictionStatus: .unrestricted,
        restrictedApps: [],
        lastSyncedAt: .now
    )
}

enum SessionStatus: Equatable {
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
