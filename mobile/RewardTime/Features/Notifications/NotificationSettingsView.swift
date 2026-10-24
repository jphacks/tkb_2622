import Combine
import SwiftUI
import UIKit
import UserNotifications

@MainActor
private final class NotificationSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequesting = false

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
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

    var detail: String {
        switch authorizationStatus {
        case .notDetermined: "通知を使うにはiPhoneの許可が必要です。"
        case .denied: "通知はiPhoneの設定で許可できます。"
        case .authorized: "このアプリから通知を表示する許可があります。"
        case .provisional: "通知は通知センターへ静かに表示されます。"
        case .ephemeral: "通知の許可は一時的です。"
        @unknown default: "iPhoneの通知設定を確認してください。"
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
                Label("iPhoneの通知許可", systemImage: model.symbol)
                    .font(.headline)
                    .foregroundStyle(model.isAllowed ? AppTheme.teal : AppTheme.primary)

                Text(model.title)
                    .font(.title3.weight(.bold))

                Text(model.detail)
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
                }
            }

            SurfaceCard {
                Label("通知配信は未接続です", systemImage: "info.circle")
                    .font(.subheadline.weight(.bold))
                Text("ここではiPhoneの通知許可だけを確認します。APNsの端末登録、グループ開始や報酬確定の配信、作業中の通知抑制はbackend未接続のため、通知は届きません。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SurfaceCard {
                Text("作業・報酬の履歴は、通知に頼らずアプリ内で確認できます。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .navigationTitle("通知設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { NotificationSettingsView() }
    }
}
