import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var screenTime = MobileScreenTimeController()
    @State private var selectedTab = 0
    @State private var pendingInvitationToken: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(screenTime: screenTime)
            }
            .tabItem { Label("ホーム", systemImage: "house") }
            .tag(0)

            NavigationStack {
                GroupView(invitationToken: $pendingInvitationToken)
            }
            .tabItem { Label("グループ", systemImage: "person.2") }
            .tag(1)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("履歴", systemImage: "chart.bar") }
            .tag(2)

            NavigationStack {
                SettingsView(screenTime: screenTime)
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(3)
        }
        .tint(AppTheme.primary)
        .task { await synchronizeUsageGrant() }
        .onOpenURL { url in
            guard let token = GroupInvitationLink.token(from: url) else { return }
            pendingInvitationToken = token
            selectedTab = 1
        }
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
