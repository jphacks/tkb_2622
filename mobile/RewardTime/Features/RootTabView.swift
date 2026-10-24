import SwiftUI

struct RootTabView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var screenTime = MobileScreenTimeController()
  @StateObject private var apiSync = MobileAPISyncCoordinator()
  @AppStorage("mobile.auth.loginDeferred") private var loginDeferred = false
  @State private var selectedTab = 0
  @State private var pendingInvitationToken: String?
  @State private var entryState: AuthenticationEntryState = .checking
  @State private var identitySyncError: String?
  @State private var isRestoringAuthentication = false

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
      case .identitySyncRequired:
        identitySyncRequiredView
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

  private var identitySyncRequiredView: some View {
    VStack(spacing: 16) {
      Label("アカウントを同期できませんでした", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(identitySyncError ?? "保存済みのログインはありますが、サーバー上のアカウント情報を確認できませんでした。")
        .font(.subheadline)
        .foregroundStyle(AppTheme.secondaryInk)
        .multilineTextAlignment(.center)
      Button("再試行") {
        entryState = .checking
        Task { await restoreAuthentication() }
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.primary)
      Button("端末内で続ける") {
        loginDeferred = true
        entryState = .localOnly
      }
      .font(.footnote)
      Button("別のアカウントでログイン") {
        Task { await signOutAndShowWelcome() }
      }
      .font(.footnote)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppTheme.background.ignoresSafeArea())
  }

  private func mainTabs(isAuthenticated: Bool) -> some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        HomeView(
          screenTime: screenTime,
          isAuthenticated: isAuthenticated,
          isVisible: selectedTab == 0,
          requestSignIn: showWelcome,
          apiSyncError: apiSync.errorMessage,
          retryAPISync: { await synchronizeUsageGrant() }
        )
          .toolbar { NotificationToolbarButton(isAuthenticated: isAuthenticated) }
      }
      .tabItem { Label("ホーム", systemImage: "house") }
      .tag(0)

      NavigationStack {
        GroupView(
          invitationToken: $pendingInvitationToken,
          isAuthenticated: isAuthenticated,
          requestSignIn: showWelcome
        )
        .toolbar { NotificationToolbarButton(isAuthenticated: isAuthenticated) }
      }
      .tabItem { Label("グループ", systemImage: "person.2") }
      .tag(1)

      NavigationStack {
        HistoryView(isAuthenticated: isAuthenticated, requestSignIn: showWelcome)
          .toolbar { NotificationToolbarButton(isAuthenticated: isAuthenticated) }
      }
      .tabItem { Label("履歴", systemImage: "chart.bar") }
      .tag(2)

      NavigationStack {
        SettingsView(screenTime: screenTime, isAuthenticated: isAuthenticated)
          .toolbar { NotificationToolbarButton(isAuthenticated: isAuthenticated) }
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
    guard !isRestoringAuthentication else { return }
    isRestoringAuthentication = true
    defer { isRestoringAuthentication = false }

    let sessionCheck = await checkAuthenticatedSession()
    let hasSession = sessionCheck.hasSession
    let needsIdentitySync = AuthenticationEntryState.needsBusinessIdentitySync(
      currentState: entryState,
      loginDeferred: loginDeferred
    )
    var identityReady = !needsIdentitySync
    if let sessionError = sessionCheck.errorDescription {
      identitySyncError = "保存済みのログイン状態を更新できませんでした: \(sessionError)"
      identityReady = false
    } else if hasSession && needsIdentitySync {
      identitySyncError = await synchronizeBusinessIdentity()
      identityReady = identitySyncError == nil
    } else if !hasSession {
      identitySyncError = nil
    }
    let nextState = AuthenticationEntryState.resolve(
      hasValidSession: hasSession,
      businessUserReady: identityReady,
      loginDeferred: loginDeferred,
      sessionCheckFailed: sessionCheck.errorDescription != nil
    )
    if nextState == .authenticated { loginDeferred = false }
    entryState = nextState
  }

  @MainActor
  private func refreshAuthenticationAfterChange() async {
    loginDeferred = false
    identitySyncError = nil
    entryState = .checking
    await restoreAuthentication()
  }

  @MainActor
  private func checkAuthenticatedSession() async -> (hasSession: Bool, errorDescription: String?) {
    guard let auth = MobileAppConfiguration.makeAuthService() else { return (false, nil) }
    if let session = auth.client.auth.currentSession, !session.isExpired { return (true, nil) }
    do {
      return (try await auth.accessToken() != nil, nil)
    } catch {
      // A refresh/network failure is not proof that the user signed out. Keep the session
      // recoverable and let the retry view explain the failure instead of showing welcome.
      return (true, AuthenticationErrorMessage.describe(error))
    }
  }

  @MainActor
  private func synchronizeBusinessIdentity() async -> String? {
    guard let auth = MobileAppConfiguration.makeAuthService(),
      let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL,
      let baseURL = URL(string: apiBaseURLText),
      let scheme = baseURL.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      baseURL.host != nil
    else {
      return "接続先を確認してください。"
    }

    do {
      let session = try await auth.client.auth.session
      let operationKey = "mobile.identity.ensureUser.operation.\(session.user.id.uuidString)"
      let defaults = UserDefaults.standard
      let operationID = (defaults.string(forKey: operationKey) ?? UUID().uuidString).lowercased()
      defaults.set(operationID, forKey: operationKey)
      let repository = IdentityAPIRepository(baseURL: baseURL, auth: auth)
      _ = try await repository.ensureUserAndFetchCurrentUser(operationID: operationID)
      defaults.removeObject(forKey: operationKey)
      return nil
    } catch {
      return "アカウント情報の確認に失敗しました: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func signOutAndShowWelcome() async {
    guard let auth = MobileAppConfiguration.makeAuthService() else {
      loginDeferred = false
      entryState = .welcome
      return
    }
    do {
      try await auth.signOutFromThisDevice()
      loginDeferred = false
      identitySyncError = nil
      entryState = .welcome
    } catch {
      identitySyncError = "ログアウトできませんでした: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func synchronizeUsageGrant() async {
    await apiSync.synchronize(
      usage: {
        let repository = try ConfiguredUsageGrantRepository()
        try await repository.synchronizeStoredActiveGrantIfPresent()
      },
      refreshHome: {
        let snapshot = try await ConfiguredHomeRepository().fetchCurrentSnapshot()
        await screenTime.reconcileServerRestriction(snapshot)
      }
    )
  }
}
