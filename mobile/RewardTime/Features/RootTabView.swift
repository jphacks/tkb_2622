import SwiftUI

struct RootTabView: View {
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
    }
}
