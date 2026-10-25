import Combine
import CryptoKit
import SwiftUI
import UIKit
import UserNotifications

@MainActor
private final class NotificationSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequesting = false
    @Published private(set) var apiStatusMessage = "サーバー登録を確認中です。"
    private let registrationGate = NotificationEndpointRegistrationGate()

    func refresh(forceRegistration: Bool = false, isAuthenticated: Bool) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        let action = NotificationEndpointSyncPolicy.resolve(
            isAuthenticated: isAuthenticated
                && MobileAppConfiguration.makeAuthService()?.authenticatedUserID != nil,
            permission: syncPermission,
            token: UserDefaults.standard.string(forKey: "mobile.apns.token")
        )
        switch action {
        case .signInRequired:
            apiStatusMessage = "通知先をサーバーと同期するにはログインしてください。"
        case .register(let token):
            await register(
                token: token,
                force: forceRegistration,
                isAuthenticated: isAuthenticated
            )
        case .requestAppleRegistration:
            UIApplication.shared.registerForRemoteNotifications()
            apiStatusMessage = "iPhoneの通知先をAppleへ登録しています。"
        case .remove:
            await removeRegisteredEndpoint()
        case .permissionRequired:
            apiStatusMessage = "通知を許可すると、iPhoneの通知先をサーバーへ登録します。"
        }
    }

    func requestAuthorization(isAuthenticated: Bool) async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh(forceRegistration: true, isAuthenticated: isAuthenticated)
    }

    func register(token: String, force: Bool = false, isAuthenticated: Bool) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        let action = NotificationEndpointSyncPolicy.resolve(
            isAuthenticated: isAuthenticated
                && MobileAppConfiguration.makeAuthService()?.authenticatedUserID != nil,
            permission: syncPermission,
            token: token
        )
        guard case .register(let authorizedToken) = action else {
            switch action {
            case .signInRequired:
                apiStatusMessage = "通知先をサーバーと同期するにはログインしてください。"
            case .remove:
                await removeRegisteredEndpoint()
            case .permissionRequired:
                apiStatusMessage = "通知を許可すると、iPhoneの通知先をサーバーへ登録します。"
            case .requestAppleRegistration:
                UIApplication.shared.registerForRemoteNotifications()
                apiStatusMessage = "iPhoneの通知先をAppleへ登録しています。"
            case .register:
                break
            }
            return
        }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        let token = authorizedToken
        let fingerprint = registrationFingerprint(token: token, environment: environment)
        let decision = fingerprint.map {
            registrationGate.beginRegistration(for: $0, force: force)
        } ?? .start
        switch decision {
        case .alreadyRegistered:
            apiStatusMessage = "通知先をサーバーに登録しました。"
            return
        case .inFlight:
            return
        case .start:
            break
        }

        do {
            try await ConfiguredNotificationEndpointRepository().register(token: token, environment: environment)
            if let fingerprint {
                registrationGate.finishRegistration(for: fingerprint, succeeded: true)
            }
            apiStatusMessage = "通知先をサーバーに登録しました。"
        } catch {
            if let fingerprint {
                registrationGate.finishRegistration(for: fingerprint, succeeded: false)
            }
            apiStatusMessage = "通知先の登録に失敗しました: \(error.localizedDescription)"
        }
    }

    private func registrationFingerprint(token: String, environment: String) -> String? {
        guard let userID = MobileAppConfiguration.makeAuthService()?.authenticatedUserID else {
            return nil
        }
        let registrationID = ConfiguredDeviceSettingsRepository().stableRegistrationID()
        let input = "\(userID)|\(registrationID)|\(environment)|\(token)"
        return SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func invalidateRegistrationCache() {
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        guard let token = UserDefaults.standard.string(forKey: "mobile.apns.token"),
              let fingerprint = registrationFingerprint(token: token, environment: environment) else {
            return
        }
        registrationGate.invalidateRegistration(for: fingerprint)
    }

    private func removeRegisteredEndpoint() async {
        do {
            try await ConfiguredNotificationEndpointRepository().delete()
            invalidateRegistrationCache()
            apiStatusMessage = "通知許可がないため、サーバーの通知先登録を解除しました。"
        } catch {
            apiStatusMessage = "通知先の解除に失敗しました: \(error.localizedDescription)"
        }
    }

    private var syncPermission: NotificationEndpointSyncPolicy.Permission {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notAllowed
        @unknown default:
            return .notAllowed
        }
    }

    func apnsRegistrationFailed() {
        apiStatusMessage = "Appleの通知サービスへ登録できません。アプリの署名設定を確認してください。"
    }

    var title: String {
        switch authorizationStatus {
        case .notDetermined: "未設定"
        case .denied: "許可されていません"
        case .authorized: "許可済み"
        case .provisional: "仮許可"
        case .ephemeral: "一時許可"
        @unknown default: "状態を確認できません"
        }
    }

    var symbol: String {
        switch authorizationStatus {
        case .notDetermined: "bell.badge"
        case .denied: "bell.slash"
        case .authorized, .provisional, .ephemeral: "bell.badge.fill"
        @unknown default: "bell"
        }
    }

    var isAllowed: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = NotificationSettingsViewModel()
    let isAuthenticated: Bool

    init(isAuthenticated: Bool = true) {
        self.isAuthenticated = isAuthenticated
    }

    var body: some View {
        ScreenContainer {
            SurfaceCard {
                HStack {
                    Label("通知", systemImage: model.symbol)
                        .font(.headline)
                        .foregroundStyle(model.isAllowed ? AppTheme.teal : AppTheme.primary)
                    Spacer()
                    Text(model.title)
                        .font(.subheadline.weight(.semibold))
                }

                Text("通知許可とiPhoneの通知先を同期し、グループの作業開始をお知らせします。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)

                Text(model.apiStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)

                if model.authorizationStatus == .notDetermined {
                    Button {
                        Task { await model.requestAuthorization(isAuthenticated: isAuthenticated) }
                    } label: {
                        Label(model.isRequesting ? "確認中…" : "通知を許可", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(model.isRequesting)
                } else if model.authorizationStatus == .denied {
                    Button {
                        model.openSystemSettings()
                    } label: {
                        Label("iPhoneの通知設定を開く", systemImage: "gear")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                } else if model.isAllowed {
                    Button {
                        Task { await model.refresh(forceRegistration: true, isAuthenticated: isAuthenticated) }
                    } label: {
                        Label("通知先を再同期", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }

        }
        .task { await model.refresh(isAuthenticated: isAuthenticated) }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAPNsTokenReceived)) { notification in
            guard let token = notification.object as? String else { return }
            Task { await model.register(token: token, isAuthenticated: isAuthenticated) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAPNsRegistrationFailed)) { _ in
            model.apnsRegistrationFailed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
            Task { await model.refresh(isAuthenticated: isAuthenticated) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh(isAuthenticated: isAuthenticated) } }
        }
        .onChange(of: isAuthenticated) { _, authenticated in
            Task { await model.refresh(isAuthenticated: authenticated) }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationToolbarButton: ToolbarContent {
    let isAuthenticated: Bool

    init(isAuthenticated: Bool = true) {
        self.isAuthenticated = isAuthenticated
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                NotificationSettingsView(isAuthenticated: isAuthenticated)
            } label: {
                Image(systemName: "bell")
            }
            .accessibilityLabel("通知")
            .accessibilityIdentifier("notificationToolbarButton")
        }
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { NotificationSettingsView(isAuthenticated: true) }
    }
}
