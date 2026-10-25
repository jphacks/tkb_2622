import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroup = "group.com.example.tkb2622.mobile"
    private let selectionKey = "mobile.screenTime.selection"

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
        guard let tokens = Self.applicationTokens(from: defaults, key: selectionKey), !tokens.isEmpty else {
            clearInvalidSelection(store: store, defaults: defaults)
            return
        }
        store.shield.applicationCategories = nil
        store.shield.applications = tokens
        defaults.set("SHIELD_STATUS_SHIELDED", forKey: "mobile.usage.localShieldStatus")
    }

    private static func applicationTokens(from defaults: UserDefaults, key: String) -> Set<ApplicationToken>? {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return nil
        }
        return selection.applicationTokens
    }

    private func clearInvalidSelection(store: ManagedSettingsStore, defaults: UserDefaults) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        defaults.set("missing_selection", forKey: "mobile.usage.monitorError")
        defaults.set("SHIELD_STATUS_ERROR", forKey: "mobile.usage.localShieldStatus")
    }

    private static func reportedSeconds(from eventName: String) -> Int? {
        guard eventName.hasPrefix("usage-seconds-") else { return nil }
        return Int(eventName.dropFirst("usage-seconds-".count))
    }
}
