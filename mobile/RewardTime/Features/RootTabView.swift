import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var screenTime = MobileScreenTimeController()

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(screenTime: screenTime)
            }
            .tabItem { Label("ホーム", systemImage: "house") }

            NavigationStack {
                GroupView()
            }
            .tabItem { Label("グループ", systemImage: "person.2") }

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("履歴", systemImage: "chart.bar") }

            NavigationStack {
                SettingsView(screenTime: screenTime)
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(AppTheme.primary)
        .task { await synchronizeUsageGrant() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await synchronizeUsageGrant() } }
        }
    }

    @MainActor
    private func synchronizeUsageGrant() async {
        if let repository = try? ConfiguredUsageGrantRepository() {
            await repository.synchronizeStoredActiveGrantIfPresent()
        }
        guard let snapshot = try? await ConfiguredHomeRepository().fetchCurrentSnapshot() else { return }
        await screenTime.reconcileServerRestriction(snapshot)
    }
}
