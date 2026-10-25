import Combine
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class MobileScreenTimeController: ObservableObject {
    @Published var selection: FamilyActivitySelection {
        didSet {
            saveSelection()
            let selectionMatchesShield = Self.hasAppliedSelection(
                from: settingsStore,
                selectedApplications: selection.applicationTokens
            )
            if hasAppliedRestriction && !selectionMatchesShield {
                settingsStore.shield.applications = nil
                settingsStore.shield.applicationCategories = nil
                hasAppliedRestriction = false
                ScreenTimeSharedStorage.defaults.set(
                    "SHIELD_STATUS_UNSHIELDED",
                    forKey: "mobile.usage.localShieldStatus"
                )
            }
        }
    }
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var deviceConfigVersion: Int64
    @Published private(set) var hasAppliedRestriction: Bool

    private let authorizationCenter: AuthorizationCenter
    private let settingsStore: ManagedSettingsStore
    private let defaults: UserDefaults
    private let selectionDefaultsKey = "mobile.screenTime.selection"
    private let selectionConfiguredDefaultsKey = "mobile.screenTime.selectionConfigured"
    private let deviceConfigVersionDefaultsKey = "mobile.screenTime.deviceConfigVersion"
    @Published private(set) var hasSelectionBeenConfigured: Bool

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        settingsStore: ManagedSettingsStore = ManagedSettingsStore(),
        defaults: UserDefaults? = nil
    ) {
        self.authorizationCenter = authorizationCenter
        self.settingsStore = settingsStore
        let resolvedDefaults = defaults ?? ScreenTimeSharedStorage.defaults
        let selectionKey = "mobile.screenTime.selection"
        let selectionConfiguredKey = "mobile.screenTime.selectionConfigured"
        let deviceConfigVersionKey = "mobile.screenTime.deviceConfigVersion"
        if defaults == nil,
           resolvedDefaults.data(forKey: selectionKey) == nil,
           let legacySelection = UserDefaults.standard.data(forKey: selectionKey) {
            resolvedDefaults.set(legacySelection, forKey: selectionKey)
            resolvedDefaults.set(
                UserDefaults.standard.bool(forKey: selectionConfiguredKey),
                forKey: selectionConfiguredKey
            )
            resolvedDefaults.set(
                UserDefaults.standard.integer(forKey: deviceConfigVersionKey),
                forKey: deviceConfigVersionKey
            )
        }
        self.defaults = resolvedDefaults
        authorizationStatus = authorizationCenter.authorizationStatus
        let storedSelection = resolvedDefaults.data(forKey: selectionDefaultsKey)
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
        selection = storedSelection
        hasSelectionBeenConfigured = resolvedDefaults.bool(forKey: selectionConfiguredDefaultsKey)
            || !storedSelection.applicationTokens.isEmpty
        let removedLegacyConfiguration = resolvedDefaults.string(forKey: "mobile.screenTime.restrictionMode") == "entireDevice"
            || resolvedDefaults.data(forKey: "mobile.screenTime.safariSelection") != nil
        resolvedDefaults.removeObject(forKey: "mobile.screenTime.restrictionMode")
        resolvedDefaults.removeObject(forKey: "mobile.screenTime.safariSelection")
        let configVersion = resolvedDefaults.integer(forKey: deviceConfigVersionDefaultsKey)
            + (removedLegacyConfiguration ? 1 : 0)
        deviceConfigVersion = Int64(configVersion)
        resolvedDefaults.set(configVersion, forKey: deviceConfigVersionDefaultsKey)

        let shieldMatchesSelection = Self.hasAppliedSelection(
            from: settingsStore,
            selectedApplications: storedSelection.applicationTokens
        )
        hasAppliedRestriction = shieldMatchesSelection
        if !shieldMatchesSelection,
           (settingsStore.shield.applications != nil || settingsStore.shield.applicationCategories != nil) {
            settingsStore.shield.applications = nil
            settingsStore.shield.applicationCategories = nil
            ScreenTimeSharedStorage.defaults.set("SHIELD_STATUS_UNSHIELDED", forKey: "mobile.usage.localShieldStatus")
        }
    }

    var backendRestrictionSettings: DeviceRestrictionSettings {
        let configured = isAuthorized && restrictedApplicationCount > 0 && !hasUnsupportedTargets
        return DeviceRestrictionSettings(
            enabled: configured,
            targetMode: "TARGET_MODE_SELECTED_APPS",
            configured: configured,
            deviceConfigVersion: deviceConfigVersion
        )
    }

    var isAuthorized: Bool {
        if authorizationStatus == .approved { return true }
        if #available(iOS 26.4, *), authorizationStatus == .approvedWithDataAccess { return true }
        return false
    }

    var selectedApplicationCount: Int { selection.applicationTokens.count }
    var restrictedApplicationTokens: Set<ApplicationToken> { selection.applicationTokens }
    var restrictedApplicationCount: Int { restrictedApplicationTokens.count }

    var hasUnsupportedTargets: Bool {
        !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var applyRestrictionUnavailableReason: String? {
        guard isAuthorized else {
            return authorizationStatus == .denied
                ? "iPhoneの設定でスクリーンタイムの許可状態を確認してください。"
                : "先に「本人利用の許可を求める」を押してください。"
        }
        if hasUnsupportedTargets {
            return "カテゴリやWebサイトはまだ適用できません。選択内容をアプリだけにしてください。"
        }
        if restrictedApplicationCount == 0 {
            return "制限するアプリを1つ以上選んでください。"
        }
        return nil
    }

    var appliedRestrictionLabel: String {
        hasAppliedRestriction ? "選択したアプリを制限中" : "作業セッション中に自動で制限"
    }

    var authorizationStatusLabel: String {
        if #available(iOS 26.4, *), authorizationStatus == .approvedWithDataAccess {
            return "許可済み（データアクセス）"
        }
        return switch authorizationStatus {
        case .notDetermined: "未確認"
        case .denied: "拒否"
        case .approved: "許可済み"
        default: "不明"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationCenter.authorizationStatus
        hasAppliedRestriction = Self.hasAppliedSelection(
            from: settingsStore,
            selectedApplications: selection.applicationTokens
        )
    }

    func requestAuthorization() async {
        isRequestingAuthorization = true
        errorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            refreshAuthorizationStatus()
            statusMessage = "スクリーンタイムの本人利用を許可しました。"
        } catch {
            refreshAuthorizationStatus()
            errorMessage = "スクリーンタイムの許可を取得できませんでした。設定を確認して再度お試しください。"
        }
    }

    @discardableResult
    func applyRestriction() -> Bool {
        guard applyRestrictionUnavailableReason == nil else {
            errorMessage = applyRestrictionUnavailableReason
            ScreenTimeSharedStorage.defaults.set("SHIELD_STATUS_ERROR", forKey: "mobile.usage.localShieldStatus")
            return false
        }
        settingsStore.shield.applicationCategories = nil
        settingsStore.shield.applications = restrictedApplicationTokens
        hasAppliedRestriction = true
        ScreenTimeSharedStorage.defaults.set("SHIELD_STATUS_SHIELDED", forKey: "mobile.usage.localShieldStatus")
        errorMessage = nil
        statusMessage = "指定したアプリをiPhoneに設定しました。対象アプリを開いてShield画面が表示されるか確認してください。"
        return true
    }

    @discardableResult
    func clearRestriction() -> Bool {
        settingsStore.shield.applications = nil
        settingsStore.shield.applicationCategories = nil
        hasAppliedRestriction = false
        ScreenTimeSharedStorage.defaults.set("SHIELD_STATUS_UNSHIELDED", forKey: "mobile.usage.localShieldStatus")
        errorMessage = nil
        statusMessage = "このアプリが設定したShieldを解除しました。"
        return true
    }

    func reconcileServerRestriction(_ snapshot: MobileHomeSnapshot) async {
        guard !snapshot.isSampleData else { return }
        refreshAuthorizationStatus()

        let shared = ScreenTimeSharedStorage.defaults
        var status = "SHIELD_STATUS_UNKNOWN"
        var failureReason = ""
        var grantID = ""

        switch snapshot.desiredRestriction {
        case .shielded:
            if applyRestriction() {
                status = "SHIELD_STATUS_SHIELDED"
            } else {
                status = "SHIELD_STATUS_ERROR"
                failureReason = errorMessage ?? "Screen Timeの制限を適用できませんでした。"
            }
        case .timedUnlock:
            guard let activeGrantID = snapshot.activeGrantID,
                  ["GRANT_STATUS_RESERVED", "GRANT_STATUS_ACTIVATED"].contains(snapshot.activeGrantStatus ?? "") else {
                if applyRestriction() {
                    status = "SHIELD_STATUS_SHIELDED"
                    failureReason = "有効な利用枠が見つからないため、制限を維持しました。"
                } else {
                    status = "SHIELD_STATUS_ERROR"
                    failureReason = errorMessage ?? "利用枠が見つからず、制限も適用できませんでした。"
                }
                break
            }

            grantID = activeGrantID
            let grantFinished = shared.string(forKey: "mobile.usage.completedGrantID") == activeGrantID
                || shared.bool(forKey: "mobile.usage.monitorIntervalEnded")
            if grantFinished {
                if applyRestriction() {
                    status = "SHIELD_STATUS_SHIELDED"
                } else {
                    status = "SHIELD_STATUS_ERROR"
                    failureReason = errorMessage ?? "利用枠終了後の制限を適用できませんでした。"
                }
            } else if DeviceActivityUsageMonitor().isMonitoring {
                if clearRestriction() {
                    status = "SHIELD_STATUS_UNSHIELDED"
                }
            } else {
                if applyRestriction() {
                    status = "SHIELD_STATUS_ERROR"
                    failureReason = "利用時間の監視が停止していたため、制限を維持しました。"
                    shared.set(status, forKey: "mobile.usage.localShieldStatus")
                } else {
                    status = "SHIELD_STATUS_ERROR"
                    failureReason = errorMessage ?? "利用時間の監視停止後に制限を適用できませんでした。"
                }
            }
        case .unrestricted, .sessionEnded:
            if clearRestriction() {
                status = "SHIELD_STATUS_UNSHIELDED"
            }
        case .unknown:
            return
        }

        guard let deviceID = snapshot.restrictionDeviceID else { return }
        let permissionStatus = isAuthorized
            ? "PERMISSION_STATUS_GRANTED"
            : (authorizationStatus == .denied ? "PERMISSION_STATUS_DENIED" : "PERMISSION_STATUS_NOT_DETERMINED")
        let serverAlreadyMatches = snapshot.restrictionAppliedRevision >= snapshot.restrictionControlRevision
            && snapshot.restrictionShieldStatus == status
            && snapshot.restrictionPermissionStatus == permissionStatus
        let operationKey = "mobile.restriction.reportOperation.\(snapshot.restrictionControlRevision).\(status)"
        let appliedAtKey = "\(operationKey).appliedAt"
        let requestFingerprintKey = "\(operationKey).requestFingerprint"
        if serverAlreadyMatches {
            shared.removeObject(forKey: operationKey)
            shared.removeObject(forKey: appliedAtKey)
            shared.removeObject(forKey: requestFingerprintKey)
            return
        }

        let reportedGrantID = status == "SHIELD_STATUS_UNSHIELDED" ? grantID : ""
        let requestFingerprint = [
            deviceID,
            String(snapshot.restrictionControlRevision),
            reportedGrantID,
            status,
            permissionStatus,
            failureReason
        ].joined(separator: "\u{1f}")
        let hasMatchingPendingRequest = shared.string(forKey: requestFingerprintKey) == requestFingerprint
            && shared.object(forKey: appliedAtKey) as? Date != nil
        let operationID: String
        let appliedAt: Date
        if hasMatchingPendingRequest,
           let pendingOperationID = shared.string(forKey: operationKey),
           let pendingAppliedAt = shared.object(forKey: appliedAtKey) as? Date {
            operationID = pendingOperationID
            appliedAt = pendingAppliedAt
        } else {
            operationID = UUID().uuidString.lowercased()
            appliedAt = Date()
            shared.set(operationID, forKey: operationKey)
            shared.set(appliedAt, forKey: appliedAtKey)
            shared.set(requestFingerprint, forKey: requestFingerprintKey)
        }
        do {
            let repository = try ConfiguredUsageGrantRepository()
            try await repository.reportRestrictionState(
                operationID: operationID,
                deviceID: deviceID,
                controlRevision: snapshot.restrictionControlRevision,
                grantID: reportedGrantID,
                shieldStatus: status,
                permissionStatus: permissionStatus,
                failureReason: failureReason,
                appliedAt: appliedAt
            )
            if status != "SHIELD_STATUS_ERROR" {
                errorMessage = nil
            }
            shared.removeObject(forKey: operationKey)
            shared.removeObject(forKey: appliedAtKey)
            shared.removeObject(forKey: requestFingerprintKey)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "制限の適用状態をbackendへ報告できませんでした。"
        }
    }

    private func saveSelection() {
        do {
            let data = try JSONEncoder().encode(selection)
            if defaults.data(forKey: selectionDefaultsKey) != data { advanceDeviceConfigVersion() }
            defaults.set(data, forKey: selectionDefaultsKey)
            defaults.set(true, forKey: selectionConfiguredDefaultsKey)
            hasSelectionBeenConfigured = true
            errorMessage = nil
        } catch {
            errorMessage = "選択したアプリをこの端末に保存できませんでした。"
        }
    }

    private func advanceDeviceConfigVersion() {
        deviceConfigVersion += 1
        defaults.set(Int(deviceConfigVersion), forKey: deviceConfigVersionDefaultsKey)
    }

    private static func hasAppliedSelection(
        from store: ManagedSettingsStore,
        selectedApplications: Set<ApplicationToken>
    ) -> Bool {
        guard let applications = store.shield.applications else { return false }
        return !selectedApplications.isEmpty && applications == selectedApplications
    }
}
