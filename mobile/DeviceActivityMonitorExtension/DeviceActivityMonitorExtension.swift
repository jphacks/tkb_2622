import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroup = "group.com.example.tkb2622.mobile"
    private let selectionKey = "mobile.screenTime.selection"
    private let alwaysAllowedSelectionKey = "mobile.screenTime.alwaysAllowedSelection"
    private let restrictionModeKey = "mobile.screenTime.restrictionMode"

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: "mobile.usage.activityName") == activity.rawValue,
              let seconds = Self.reportedSeconds(from: event.rawValue),
              let grantID = defaults.string(forKey: "mobile.usage.activeGrantID"),
              seconds <= defaults.integer(forKey: "mobile.usage.reservedSeconds") else {
            return
        }

        let measuredSeconds = max(defaults.integer(forKey: "mobile.usage.measuredSeconds"), seconds)
        defaults.set(measuredSeconds, forKey: "mobile.usage.measuredSeconds")
        defaults.set(Date(), forKey: "mobile.usage.measuredAt")
        if measuredSeconds >= defaults.integer(forKey: "mobile.usage.reservedSeconds") {
            applyShield(using: defaults)
            defaults.set(grantID, forKey: "mobile.usage.completedGrantID")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: "mobile.usage.activityName") == activity.rawValue,
              defaults.string(forKey: "mobile.usage.activeGrantID") != nil else {
            return
        }
        applyShield(using: defaults)
        defaults.set(true, forKey: "mobile.usage.monitorIntervalEnded")
    }

    private func applyShield(using defaults: UserDefaults) {
        let store = ManagedSettingsStore()
        let mode = defaults.string(forKey: restrictionModeKey) ?? "selectedApplications"
        if mode == "entireDevice" {
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: Self.alwaysAllowedTokens(from: defaults, key: alwaysAllowedSelectionKey))
            defaults.set("SHIELD_STATUS_SHIELDED", forKey: "mobile.usage.localShieldStatus")
            return
        }

        guard let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
              !selection.applicationTokens.isEmpty else {
            store.shield.applications = nil
            store.shield.applicationCategories = .all()
            defaults.set("missing_selection", forKey: "mobile.usage.monitorError")
            defaults.set("SHIELD_STATUS_SHIELDED", forKey: "mobile.usage.localShieldStatus")
            return
        }
        store.shield.applicationCategories = nil
        store.shield.applications = selection.applicationTokens
        defaults.set("SHIELD_STATUS_SHIELDED", forKey: "mobile.usage.localShieldStatus")
    }

    private static func alwaysAllowedTokens(from defaults: UserDefaults, key: String) -> Set<ApplicationToken> {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return []
        }
        return selection.applicationTokens
    }

    private static func reportedSeconds(from eventName: String) -> Int? {
        guard eventName.hasPrefix("usage-seconds-") else { return nil }
        return Int(eventName.dropFirst("usage-seconds-".count))
    }
}
