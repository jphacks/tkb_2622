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

    private let authorizationCenter: AuthorizationCenter
    private let settingsStore: ManagedSettingsStore
    private let defaults: UserDefaults
    private let selectionDefaultsKey = "mobile.screenTime.selection"

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        settingsStore: ManagedSettingsStore = ManagedSettingsStore(),
        defaults: UserDefaults = .standard
    ) {
        self.authorizationCenter = authorizationCenter
        self.settingsStore = settingsStore
        self.defaults = defaults
        authorizationStatus = authorizationCenter.authorizationStatus
        selection = defaults.data(forKey: selectionDefaultsKey)
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
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

    var canApplySelectedApps: Bool {
        isAuthorized && selectedApplicationCount > 0 && !hasUnsupportedTargets
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

    func applySelectedAppsForDebug() {
        guard canApplySelectedApps else { return }
        settingsStore.shield.applications = selection.applicationTokens
        errorMessage = nil
        statusMessage = "選択したアプリにShieldを設定しました。対象アプリを開いて確認してください。"
    }

    func clearShieldForDebug() {
        guard isAuthorized else { return }
        settingsStore.shield.applications = nil
        errorMessage = nil
        statusMessage = "このアプリが設定したShieldを解除しました。"
    }

    private func saveSelection() {
        do {
            defaults.set(try JSONEncoder().encode(selection), forKey: selectionDefaultsKey)
        } catch {
            errorMessage = "選択したアプリをこの端末に保存できませんでした。"
        }
    }
}
