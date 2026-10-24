import SwiftUI

struct RootTabView: View {
  private enum EntryState {
    case checking
    case welcome
    case authenticated
    case localOnly
  }

  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var screenTime = MobileScreenTimeController()
  @AppStorage("mobile.auth.loginDeferred") private var loginDeferred = false
  @State private var selectedTab = 0
  @State private var pendingInvitationToken: String?
  @State private var entryState: EntryState = .checking

  var body: some View {
    Group {
      switch entryState {
      case .checking:
        ProgressView("ログイン状態を確認中…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(AppTheme.background.ignoresSafeArea())
      case .welcome:
        AuthenticationWelcomeView {
          loginDeferred = true
          entryState = .localOnly
        }
      case .authenticated:
        mainTabs(isAuthenticated: true)
      case .localOnly:
        mainTabs(isAuthenticated: false)
      }
    }
    .task { await restoreAuthentication() }
    .onReceive(NotificationCenter.default.publisher(for: .mobileAuthenticationChanged)) { _ in
      Task { await refreshAuthenticationAfterChange() }
    }
    .onOpenURL { url in
      guard let token = GroupInvitationLink.token(from: url) else { return }
      pendingInvitationToken = token
      selectedTab = 1
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await restoreAuthentication() } }
    }
  }

  private func mainTabs(isAuthenticated: Bool) -> some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        HomeView(
          screenTime: screenTime, isAuthenticated: isAuthenticated, requestSignIn: showWelcome)
      }
      .tabItem { Label("ホーム", systemImage: "house") }
      .tag(0)

      NavigationStack {
        GroupView(
          invitationToken: $pendingInvitationToken,
          isAuthenticated: isAuthenticated,
          requestSignIn: showWelcome
        )
      }
      .tabItem { Label("グループ", systemImage: "person.2") }
      .tag(1)

      NavigationStack {
        HistoryView(isAuthenticated: isAuthenticated, requestSignIn: showWelcome)
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
    .task { if isAuthenticated { await synchronizeUsageGrant() } }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active && isAuthenticated { Task { await synchronizeUsageGrant() } }
    }
  }

  private func showWelcome() {
    loginDeferred = false
    entryState = .welcome
  }

  @MainActor
  private func restoreAuthentication() async {
    let hasSession = await hasAuthenticatedSession()

    if hasSession {
      loginDeferred = false
      entryState = .authenticated
    } else if loginDeferred {
      entryState = .localOnly
    } else {
      entryState = .welcome
    }
  }

  @MainActor
  private func refreshAuthenticationAfterChange() async {
    let hasSession = await hasAuthenticatedSession()

    if hasSession {
      loginDeferred = false
      entryState = .authenticated
    } else {
      loginDeferred = false
      entryState = .welcome
    }
  }

  @MainActor
  private func hasAuthenticatedSession() async -> Bool {
    guard let auth = MobileAppConfiguration.makeAuthService() else { return false }
    if let session = auth.client.auth.currentSession, !session.isExpired { return true }
    return (try? await auth.accessToken()) != nil
  }

  @MainActor
  private func synchronizeUsageGrant() async {
    if let repository = try? ConfiguredUsageGrantRepository() {
      await repository.synchronizeStoredActiveGrantIfPresent()
    }
    guard let snapshot = try? await ConfiguredHomeRepository().fetchCurrentSnapshot() else {
      return
    }
    await screenTime.reconcileServerRestriction(snapshot)
  }
}
