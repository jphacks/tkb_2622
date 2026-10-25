import Foundation

struct MobileHomeSnapshot {
    let sessionStatus: SessionStatus
    let elapsedMinutes: Int?
    let minimumSeconds: Int?
    let minimumProgress: Double?
    let minimumReached: Bool
    let rewardBalanceSeconds: Int
    let desiredRestriction: DesiredRestrictionMode
    let restrictionStatus: RestrictionStatus
    let restrictedApps: [String]
    let restrictedApplicationCount: Int?
    let lastSyncedAt: Date
    let isSampleData: Bool
    let sessionID: String?
    let sessionVersion: Int64?
    let restrictionDeviceID: String?
    let restrictionControlRevision: Int64
    let restrictionAppliedRevision: Int64
    let restrictionShieldStatus: String
    let restrictionPermissionStatus: String
    let activeGrantID: String?
    let activeGrantReservedSeconds: Int?
    let activeGrantStatus: String?

    var rewardBalanceMinutes: Int { rewardBalanceSeconds / 60 }

    static let workingSample = MobileHomeSnapshot(
        sessionStatus: .working,
        elapsedMinutes: 48,
        minimumSeconds: 60 * 60,
        minimumProgress: 0.8,
        minimumReached: false,
        rewardBalanceSeconds: 32 * 60,
        desiredRestriction: .shielded,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true,
        sessionID: nil,
        sessionVersion: nil,
        restrictionDeviceID: nil,
        restrictionControlRevision: 0,
        restrictionAppliedRevision: 0,
        restrictionShieldStatus: "SHIELD_STATUS_SHIELDED",
        restrictionPermissionStatus: "PERMISSION_STATUS_GRANTED",
        activeGrantID: nil,
        activeGrantReservedSeconds: nil,
        activeGrantStatus: nil
    )

    static let pausedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedMinutes: 48,
        minimumSeconds: 60 * 60,
        minimumProgress: 0.8,
        minimumReached: false,
        rewardBalanceSeconds: 42 * 60,
        desiredRestriction: .shielded,
        restrictionStatus: .restricted,
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true,
        sessionID: "sample-paused-session",
        sessionVersion: 1,
        restrictionDeviceID: nil,
        restrictionControlRevision: 0,
        restrictionAppliedRevision: 0,
        restrictionShieldStatus: "SHIELD_STATUS_SHIELDED",
        restrictionPermissionStatus: "PERMISSION_STATUS_GRANTED",
        activeGrantID: nil,
        activeGrantReservedSeconds: nil,
        activeGrantStatus: nil
    )

    static let releasedSample = MobileHomeSnapshot(
        sessionStatus: .paused,
        elapsedMinutes: 48,
        minimumSeconds: 60 * 60,
        minimumProgress: 0.8,
        minimumReached: false,
        rewardBalanceSeconds: 32 * 60,
        desiredRestriction: .timedUnlock,
        restrictionStatus: .temporarilyReleased(endsAt: .now.addingTimeInterval(10 * 60)),
        restrictedApps: ["YouTube", "X", "Instagram", "TikTok", "Safari", "Netflix"],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true,
        sessionID: "sample-released-session",
        sessionVersion: 1,
        restrictionDeviceID: nil,
        restrictionControlRevision: 0,
        restrictionAppliedRevision: 0,
        restrictionShieldStatus: "SHIELD_STATUS_UNSHIELDED",
        restrictionPermissionStatus: "PERMISSION_STATUS_GRANTED",
        activeGrantID: nil,
        activeGrantReservedSeconds: nil,
        activeGrantStatus: nil
    )

    static let noSessionSample = MobileHomeSnapshot(
        sessionStatus: .noSession,
        elapsedMinutes: nil,
        minimumSeconds: nil,
        minimumProgress: nil,
        minimumReached: false,
        rewardBalanceSeconds: 0,
        desiredRestriction: .unrestricted,
        restrictionStatus: .unrestricted,
        restrictedApps: [],
        restrictedApplicationCount: nil,
        lastSyncedAt: .now,
        isSampleData: true,
        sessionID: nil,
        sessionVersion: nil,
        restrictionDeviceID: nil,
        restrictionControlRevision: 0,
        restrictionAppliedRevision: 0,
        restrictionShieldStatus: "SHIELD_STATUS_UNSHIELDED",
        restrictionPermissionStatus: "PERMISSION_STATUS_GRANTED",
        activeGrantID: nil,
        activeGrantReservedSeconds: nil,
        activeGrantStatus: nil
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
