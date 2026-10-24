import Combine
import ActivityKit
import SwiftUI
import WidgetKit

@MainActor
final class FriendFocusDemoStore: ObservableObject {
    @Published private(set) var snapshot: SharedFocusSnapshot
    @Published private(set) var message: String

    init() {
        snapshot = SharedFocusStore.load()
        message = Self.hasSharedContainer ? "App Group共有領域を利用できます。" : "App Groupを使えません。署名設定を確認してください。"
    }

    func setFocusing(_ isFocusing: Bool) async {
        let updatedSnapshot = SharedFocusSnapshot(
            friendName: "友だち",
            isFocusing: isFocusing,
            updatedAt: .now
        )

        guard SharedFocusStore.save(updatedSnapshot) else {
            message = "共有状態を保存できません。App Groupsの署名設定を確認してください。"
            return
        }

        snapshot = updatedSnapshot
        WidgetCenter.shared.reloadTimelines(ofKind: SharedFocusStore.widgetKind)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "状態を保存しました。Live Activitiesはこのデバイスで許可されていません。"
            return
        }

        let content = ActivityContent(
            state: FriendFocusActivityAttributes.ContentState(isFocusing: isFocusing, updatedAt: .now),
            staleDate: nil
        )

        if let activity = Activity<FriendFocusActivityAttributes>.activities.first {
            await activity.update(content)
            message = "状態を保存し、ウィジェットとLive Activityを更新しました。"
        } else if isFocusing {
            do {
                _ = try Activity.request(
                    attributes: FriendFocusActivityAttributes(friendName: updatedSnapshot.friendName),
                    content: content,
                    pushType: nil
                )
                message = "状態を保存し、ウィジェットとLive Activityを開始しました。"
            } catch {
                message = "ウィジェット状態は保存しましたが、Live Activityを開始できませんでした: \(error.localizedDescription)"
            }
        } else {
            message = "共有状態を保存し、ウィジェットの更新を要求しました。"
        }
    }

    func endLiveActivity() async {
        let activities = Activity<FriendFocusActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        message = activities.isEmpty ? "終了中のLive Activityはありません。" : "Live Activityを終了しました。"
    }

    private static var hasSharedContainer: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedFocusStore.appGroupID) != nil
    }
}

struct ContentView: View {
    @StateObject private var store = FriendFocusDemoStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("友だち集中ウィジェット")
                    .font(.title2.bold())

                Text(store.snapshot.isFocusing ? "🐱‍💻" : "🐱☕️")
                    .font(.system(size: 76))
                    .accessibilityIdentifier("friendCharacter")

                VStack(spacing: 6) {
                    Text(store.snapshot.isFocusing ? "友だちは集中しています" : "友だちは休憩中です")
                        .font(.headline)
                    Text("更新: \(store.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("友だちが集中を開始") {
                    Task { await store.setFocusing(true) }
                }
                .buttonStyle(.borderedProminent)

                Button("友だちが集中を終了") {
                    Task { await store.setFocusing(false) }
                }
                .buttonStyle(.bordered)

                Button("Live Activityを終了") {
                    Task { await store.endLiveActivity() }
                }
                .buttonStyle(.bordered)

                Text(store.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("このPoCは同じiPhone内で友だち状態を模擬します。別端末との通信は行いません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("PoC")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
