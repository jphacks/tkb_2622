import Combine
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class MobileScreenTimeController: ObservableObject {
    @Published var selection: FamilyActivitySelection {
        didSet { saveSelection() }
    }
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published var restrictionMode: LocalRestrictionMode {
        didSet {
            defaults.set(restrictionMode.rawValue, forKey: restrictionModeDefaultsKey)
            errorMessage = nil
        }
    }
    @Published private(set) var appliedRestrictionMode: LocalRestrictionMode?

    private let authorizationCenter: AuthorizationCenter
    private let settingsStore: ManagedSettingsStore
    private let defaults: UserDefaults
    private let selectionDefaultsKey = "mobile.screenTime.selection"
    private let selectionConfiguredDefaultsKey = "mobile.screenTime.selectionConfigured"
    private let restrictionModeDefaultsKey = "mobile.screenTime.restrictionMode"
    @Published private(set) var hasSelectionBeenConfigured: Bool

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        settingsStore: ManagedSettingsStore = ManagedSettingsStore(),
        defaults: UserDefaults = .standard
    ) {
        self.authorizationCenter = authorizationCenter
        self.settingsStore = settingsStore
        self.defaults = defaults
        authorizationStatus = authorizationCenter.authorizationStatus
        let storedSelection = defaults.data(forKey: selectionDefaultsKey)
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
        selection = storedSelection
        hasSelectionBeenConfigured = defaults.bool(forKey: selectionConfiguredDefaultsKey)
            || !storedSelection.applicationTokens.isEmpty
        restrictionMode = defaults.string(forKey: restrictionModeDefaultsKey)
            .flatMap(LocalRestrictionMode.init(rawValue:)) ?? .selectedApplications
        appliedRestrictionMode = Self.readAppliedMode(from: settingsStore)
    }

    var isAuthorized: Bool {
        if authorizationStatus == .approved { return true }
        if #available(iOS 26.4, *), authorizationStatus == .approvedWithDataAccess { return true }
        return false
    }

    var selectedApplicationCount: Int { selection.applicationTokens.count }

    var hasUnsupportedTargets: Bool {
        !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var applyRestrictionUnavailableReason: String? {
        guard isAuthorized else {
            return authorizationStatus == .denied
                ? "iPhoneの設定でスクリーンタイムの許可状態を確認してください。"
                : "先に「本人利用の許可を求める」を押してください。"
        }
        if restrictionMode == .selectedApplications && hasUnsupportedTargets {
            return "カテゴリやWebサイトはまだ適用できません。選択内容をアプリだけにしてください。"
        }
        if restrictionMode == .selectedApplications && selectedApplicationCount == 0 {
            return "先に制限するアプリを1つ以上選んでください。"
        }
        return nil
    }

    var appliedRestrictionLabel: String {
        switch appliedRestrictionMode {
        case .selectedApplications: "選んだアプリを適用中"
        case .entireDevice: "標準以外を制限中"
        case nil: "制限は適用されていません"
        }
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
        appliedRestrictionMode = Self.readAppliedMode(from: settingsStore)
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

    func applyRestriction() {
        guard applyRestrictionUnavailableReason == nil else {
            errorMessage = applyRestrictionUnavailableReason
            return
        }
        switch restrictionMode {
        case .selectedApplications:
            settingsStore.shield.applicationCategories = nil
            settingsStore.shield.applications = selection.applicationTokens
        case .entireDevice:
            settingsStore.shield.applications = nil
            settingsStore.shield.applicationCategories = .all()
        }
        appliedRestrictionMode = restrictionMode
        errorMessage = nil
        statusMessage = "\(restrictionMode.appliedDescription)をiPhoneに設定しました。対象アプリを開いてShield画面が表示されるか確認してください。"
    }

    func clearRestriction() {
        settingsStore.shield.applications = nil
        settingsStore.shield.applicationCategories = nil
        appliedRestrictionMode = nil
        errorMessage = nil
        statusMessage = "このアプリが設定したShieldを解除しました。"
    }

    private func saveSelection() {
        do {
            defaults.set(try JSONEncoder().encode(selection), forKey: selectionDefaultsKey)
            defaults.set(true, forKey: selectionConfiguredDefaultsKey)
            hasSelectionBeenConfigured = true
            errorMessage = nil
        } catch {
            errorMessage = "選択したアプリをこの端末に保存できませんでした。"
        }
    }

    private static func readAppliedMode(from store: ManagedSettingsStore) -> LocalRestrictionMode? {
        if store.shield.applicationCategories != nil { return .entireDevice }
        if let applications = store.shield.applications, !applications.isEmpty { return .selectedApplications }
        return nil
    }
}

enum LocalRestrictionMode: String, CaseIterable, Identifiable {
    case selectedApplications
    case entireDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedApplications: "選んだアプリを制限"
        case .entireDevice: "標準以外を制限"
        }
    }

    var detail: String {
        switch self {
        case .selectedApplications: "下で選んだアプリにShieldを設定します。"
        case .entireDevice: "標準アプリ以外にShieldを設定します。iPhone自体をロックする機能ではありません。"
        }
    }

    var appliedDescription: String {
        switch self {
        case .selectedApplications: "選択したアプリの制限"
        case .entireDevice: "標準以外のアプリ制限"
        }
    }
}
