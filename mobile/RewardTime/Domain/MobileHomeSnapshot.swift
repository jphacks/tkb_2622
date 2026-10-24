import Foundation

struct MobileHomeSnapshot {
    let sessionStatus: SessionStatus
    let elapsedMinutes: Int?
    let minimumMinutes: Int?
    let rewardBalanceMinutes: Int
    let desiredRestriction: DesiredRestrictionMode
    let restrictionStatus: RestrictionStatus
    let restrictedApps: [String]
    let restrictedApplicationCount: Int?
    let lastSyncedAt: Date
    let isSampleData: Bool

    static let workingSample = MobileHomeSnapshot(
        sessionStatus: .working,
        elapsedMinutes: 48,
        minimumMinutes: 60,
        rewardBalanceMinutes: 32,
        desiredRestriction: .shielded,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true
    )

    static let pausedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedMinutes: 48,
        minimumMinutes: 60,
        rewardBalanceMinutes: 42,
        desiredRestriction: .shielded,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true
    )

    static let releasedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedMinutes: 48,
        minimumMinutes: 60,
        rewardBalanceMinutes: 32,
        desiredRestriction: .timedUnlock,
        restrictionStatus: .temporarilyReleased(endsAt: .now.addingTimeInterval(10 * 60)),
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true
    )

    static let noSessionSample = MobileHomeSnapshot(
        sessionStatus: .noSession,
        elapsedMinutes: nil,
        minimumMinutes: nil,
        rewardBalanceMinutes: 0,
        desiredRestriction: .unrestricted,
        restrictionStatus: .unrestricted,
        restrictedApps: [],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true
    )
}

enum SessionStatus: Equatable {
    case noSession
    case working
    case paused
}

enum DesiredRestrictionMode {
    case unrestricted
    case shielded
    case timedUnlock
    case sessionEnded
    case unknown
}

enum RestrictionStatus {
    case unrestricted
    case restricted
    case temporarilyReleased(endsAt: Date?)
    case notConfirmed
    case failed
}
