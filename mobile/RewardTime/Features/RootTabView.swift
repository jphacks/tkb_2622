import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
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
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(AppTheme.primary)
    }
}
