import FamilyControls
import ManagedSettings
import Combine
import Foundation

@MainActor
final class ScreenTimePrototype: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let authorizationCenter = AuthorizationCenter.shared
    private let settingsStore = ManagedSettingsStore()

    var isAuthorized: Bool {
        authorizationStatus == .approved || authorizationStatus == .approvedWithDataAccess
    }

    var selectedApplicationCount: Int {
        selection.applicationTokens.count
    }

    var canApplyShield: Bool {
        isAuthorized && selectedApplicationCount > 0
    }

    var authorizationStatusLabel: String {
        switch authorizationStatus {
        case .notDetermined:
            "未確認"
        case .denied:
            "拒否"
        case .approved:
            "許可済み"
        case .approvedWithDataAccess:
            "許可済み（データアクセス）"
        @unknown default:
            "不明"
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
            statusMessage = "本人利用の認可が完了しました。"
        } catch {
            refreshAuthorizationStatus()
            errorMessage = "認可に失敗しました: \(error.localizedDescription)"
        }
    }

    func applyShield() {
        guard canApplyShield else { return }

        settingsStore.shield.applications = selection.applicationTokens
        errorMessage = nil
        statusMessage = "選択したアプリにShieldを設定しました。対象アプリを開いて実機で確認してください。"
    }

    func clearShield() {
        settingsStore.shield.applications = nil
        errorMessage = nil
        statusMessage = "このPoCが設定したShieldを解除しました。"
    }
}
