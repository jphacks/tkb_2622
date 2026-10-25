import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum ScreenTimeSharedStorage {
    static let appGroup = "group.com.example.tkb2622.mobile"
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
}

struct DeviceActivityUsageMonitor {
    private let center = DeviceActivityCenter()
    private let defaults = ScreenTimeSharedStorage.defaults

    var isMonitoring: Bool {
        guard let rawName = defaults.string(forKey: "mobile.usage.activityName") else { return false }
        return center.activities.contains(DeviceActivityName(rawName))
    }

    func start(
        operationID: String,
        reservedSeconds: Int,
        applications: Set<ApplicationToken>
    ) throws {
        guard reservedSeconds > 0, reservedSeconds.isMultiple(of: 60) else {
            throw DeviceActivityUsageMonitorError.invalidDuration
        }
        guard !applications.isEmpty else {
            throw DeviceActivityUsageMonitorError.noSelectedApplications
        }
        if defaults.string(forKey: "mobile.usage.activeGrantID") != nil,
           defaults.string(forKey: "mobile.usage.pendingOperationID") != operationID {
            throw DeviceActivityUsageMonitorError.anotherGrantIsActive
        }

        let activityName = DeviceActivityName("usage-\(operationID)")
        if center.activities.contains(activityName) {
            return
        }
        let now = Date()
        let end = now.addingTimeInterval(2 * 60 * 60)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dateParts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(dateParts, from: now),
            intervalEnd: calendar.dateComponents(dateParts, from: end),
            repeats: false
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for seconds in stride(from: 60, through: reservedSeconds, by: 60) {
            let eventName = DeviceActivityEvent.Name("usage-seconds-\(seconds)")
            let threshold = DateComponents(minute: seconds / 60)
            if #available(iOS 17.4, *) {
                events[eventName] = DeviceActivityEvent(
                    applications: applications,
                    categories: [],
                    webDomains: [],
                    threshold: threshold,
                    includesPastActivity: false
                )
            } else {
                events[eventName] = DeviceActivityEvent(
                    applications: applications,
                    categories: [],
                    webDomains: [],
                    threshold: threshold
                )
            }
        }

        defaults.set(operationID, forKey: "mobile.usage.pendingOperationID")
        defaults.set(activityName.rawValue, forKey: "mobile.usage.activityName")
        defaults.set(reservedSeconds, forKey: "mobile.usage.reservedSeconds")
        defaults.set(0, forKey: "mobile.usage.measuredSeconds")
        defaults.set(now, forKey: "mobile.usage.unlockedAt")
        defaults.removeObject(forKey: "mobile.usage.completedGrantID")
        defaults.removeObject(forKey: "mobile.usage.monitorError")

        try center.startMonitoring(activityName, during: schedule, events: events)
    }

    func activate(grantID: String, controlRevision: Int64) {
        defaults.set(grantID, forKey: "mobile.usage.activeGrantID")
        defaults.set(String(controlRevision), forKey: "mobile.usage.controlRevision")
        defaults.set("SHIELD_STATUS_UNSHIELDED", forKey: "mobile.usage.localShieldStatus")
        defaults.removeObject(forKey: "mobile.usage.pendingOperationID")
    }

    func stop() {
        stopMonitoring()
        defaults.removeObject(forKey: "mobile.usage.activeGrantID")
        defaults.removeObject(forKey: "mobile.usage.pendingOperationID")
        defaults.removeObject(forKey: "mobile.usage.activityName")
        defaults.removeObject(forKey: "mobile.usage.reservedSeconds")
        defaults.removeObject(forKey: "mobile.usage.measuredSeconds")
        defaults.removeObject(forKey: "mobile.usage.measuredAt")
        defaults.removeObject(forKey: "mobile.usage.completedGrantID")
        defaults.removeObject(forKey: "mobile.usage.monitorIntervalEnded")
        defaults.removeObject(forKey: "mobile.usage.monitorError")
    }

    func stopMonitoring() {
        if let rawName = defaults.string(forKey: "mobile.usage.activityName") {
            center.stopMonitoring([DeviceActivityName(rawName)])
        }
    }
}

enum DeviceActivityUsageMonitorError: Error, LocalizedError {
    case invalidDuration
    case noSelectedApplications
    case anotherGrantIsActive

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "利用時間は1分単位で指定してください。"
        case .noSelectedApplications:
            "利用時間を計測するアプリを先に選んでください。"
        case .anotherGrantIsActive:
            "利用中の枠を先に同期または終了してください。"
        }
    }
}
