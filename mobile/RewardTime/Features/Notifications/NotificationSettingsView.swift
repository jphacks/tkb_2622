import Combine
import SwiftUI
import UIKit
import UserNotifications

@MainActor
private final class NotificationSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequesting = false
    @Published private(set) var apiStatusMessage = "サーバー登録を確認中です。"

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if isAllowed {
            if let token = UserDefaults.standard.string(forKey: "mobile.apns.token"), !token.isEmpty {
                await register(token: token)
            } else {
                UIApplication.shared.registerForRemoteNotifications()
                apiStatusMessage = "iPhoneの通知先をAppleへ登録しています。"
            }
        } else if authorizationStatus == .denied {
            do {
                try await ConfiguredNotificationEndpointRepository().delete()
                apiStatusMessage = "通知許可がないため、サーバーの通知先登録を解除しました。"
            } catch {
                apiStatusMessage = "通知先の解除に失敗しました: \(error.localizedDescription)"
            }
        } else {
            apiStatusMessage = "通知を許可すると、iPhoneの通知先をサーバーへ登録します。"
        }
    }

    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
    }

    func register(token: String) async {
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        do {
            try await ConfiguredNotificationEndpointRepository().register(token: token, environment: environment)
            apiStatusMessage = "通知先をサーバーに登録しました。"
        } catch {
            apiStatusMessage = "通知先の登録に失敗しました: \(error.localizedDescription)"
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
                        Task { await model.requestAuthorization() }
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
                        Task { await model.refresh() }
                    } label: {
                        Label("通知先を再同期", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }

        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAPNsTokenReceived)) { notification in
            guard let token = notification.object as? String else { return }
            Task { await model.register(token: token) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAPNsRegistrationFailed)) { _ in
            model.apnsRegistrationFailed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
            Task { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationToolbarButton: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                NotificationSettingsView()
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
        NavigationStack { NotificationSettingsView() }
    }
}
