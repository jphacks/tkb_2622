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

                Text("アプリのお知らせ配信は準備中です。")
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

        }
        .task { await model.refresh() }
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
