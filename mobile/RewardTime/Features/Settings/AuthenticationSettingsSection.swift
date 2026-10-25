import Supabase
import SwiftUI

struct AuthenticationSettingsSection: View {
  var showsHeading = true
  var showsDeveloperConfiguration = false
  var allowsAutomaticAPISync = true
  var onAuthenticationChanged: () -> Void = {}
  @AppStorage("mobile.supabase.projectURL") private var projectURLText = ""
  @AppStorage("mobile.supabase.publishableKey") private var publishableKey = ""
  @AppStorage("mobile.api.baseURL") private var apiBaseURLText = MobileAppConfiguration.connectAPIBaseURLDefault
  @AppStorage("mobile.auth.lastEmail") private var lastEmail = ""

  @State private var email = ""
  @State private var otp = ""
  @State private var sessionRestoreGate = AuthenticationSessionRestoreGate()
  @State private var isOTPRequested = false
  /// The address the latest code was sent to. Verification always uses this value.
  @State private var requestedEmail: String?
  @State private var isWorking = false
  @State private var auth: SupabaseAuthService?
  @State private var authenticatedEmail: String?
  @State private var identity: MobileIdentity?
  @State private var displayNameDraft = ""
  @State private var avatarSelection = ProfileAvatar.defaultAvatar.rawValue
  @State private var hasPendingAvatarChoice = false
  @State private var isShowingAvatarPicker = false
  @State private var message: String?
  @State private var isError = false

  var body: some View {
    SurfaceCard {
      if showsHeading {
        Label("アカウント", systemImage: "person.crop.circle")
          .font(.subheadline.weight(.bold))
      }

      #if DEBUG
        if showsDeveloperConfiguration {
          DisclosureGroup("開発者向け接続設定") {
          TextField("Supabase Project URL", text: $projectURLText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("supabaseProjectURL")

          TextField("Supabase公開キー", text: $publishableKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("supabasePublishableKey")

          TextField("Connect API URL", text: $apiBaseURLText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("connectAPIBaseURL")
          if !MobileAppConfiguration.isSimulator && MobileAppConfiguration.isLoopbackURL(apiBaseURLText) {
            Text("127.0.0.1はiPhone自身を指します。実機ではMacのLAN IPを使ってください。")
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
          }
          .textFieldStyle(.roundedBorder)
          .font(.footnote)
          .accessibilityIdentifier("developerConnectionSettings")
        }
      #else
        if hasConnectionConfiguration {
          Label("接続済み", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(AppTheme.teal)
        } else {
          Label("接続設定がありません", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
          .foregroundStyle(.red)
        }
      #endif

      if identity == nil && !showsHeading {
        Label("プロフィールアイコン", systemImage: "person.crop.circle")
          .font(.subheadline.weight(.semibold))
        ProfileAvatarPicker(selection: $avatarSelection)
        Text("選んだアイコンは登録時に保存され、ログイン後も変更できます。")
          .font(.caption)
          .foregroundStyle(AppTheme.secondaryInk)
      }

      if let identity {
        identityView(identity)
      } else if let authenticatedEmail {
        authenticatedSessionView(email: authenticatedEmail)
      } else {
        TextField("メールアドレス", text: $email)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textFieldStyle(.roundedBorder)
          .disabled(isOTPRequested)
          .accessibilityIdentifier("authEmail")

        if isOTPRequested {
          Button("メールアドレスを変更") {
            resetOTPRequest()
          }
          .font(.caption)
          .disabled(isWorking)
        }

        Button {
          Task { await requestOTP() }
        } label: {
          Label(isOTPRequested ? "確認コードを再送" : "確認コードを送信", systemImage: "envelope")
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.primary)
        .accessibilityIdentifier("sendEmailOTP")
        .disabled(
          isWorking
            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !hasConnectionConfiguration
        )

        if isOTPRequested {
          TextField("メールに届いた確認コード", text: $otp)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("authOTP")

          Button {
            Task { await verifyOTP() }
          } label: {
            Label("ログイン", systemImage: "checkmark.shield")
              .frame(maxWidth: .infinity, minHeight: 42)
          }
          .buttonStyle(.bordered)
          .disabled(isWorking || !EmailOTPInput.isPlausibleCode(EmailOTPInput.normalizedCode(otp)))
        }
      }

      if let message {
        Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
          .font(.caption)
          .foregroundStyle(isError ? .red : AppTheme.secondaryInk)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("authenticationStatus")
      }

      if isWorking {
        ProgressView("処理中…")
          .font(.caption)
      }
    }
    .onAppear {
      if email.isEmpty { email = lastEmail }
      guard sessionRestoreGate.begin() else { return }
      Task { await restoreSessionIfPresent() }
    }
    .onChange(of: identity?.displayName) { _, newValue in
      if let newValue { displayNameDraft = newValue }
    }
    .onChange(of: identity?.avatarID) { _, newValue in
      guard let newValue, !hasPendingAvatarChoice else { return }
      avatarSelection = newValue
    }
    .onChange(of: avatarSelection) { _, newValue in
      hasPendingAvatarChoice = identity?.avatarID != newValue
    }
  }

  @ViewBuilder
  private func identityView(_ identity: MobileIdentity) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("ログイン済み", systemImage: "checkmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.teal)
      HStack(spacing: 10) {
        ProfileAvatarImage(avatarID: identity.avatarID, size: 48)
        Text("プロフィールアイコン")
          .font(.caption.weight(.semibold))
        Spacer()
        Button(isShowingAvatarPicker ? "閉じる" : "変更") {
          isShowingAvatarPicker.toggle()
          if !isShowingAvatarPicker { avatarSelection = identity.avatarID }
        }
        .font(.caption.weight(.semibold))
      }
      if isShowingAvatarPicker {
        ProfileAvatarPicker(selection: $avatarSelection)
        Button("アイコンを保存") {
          Task { await saveAvatar() }
        }
        .buttonStyle(.bordered)
        .disabled(isWorking || !hasPendingAvatarChoice)
      }
      Text("グループに表示する名前")
        .font(.caption.weight(.semibold))
      TextField("1〜30文字", text: $displayNameDraft)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("groupDisplayName")
      Button("表示名を保存") {
        Task { await saveDisplayName() }
      }
      .buttonStyle(.bordered)
      .disabled(
        isWorking || displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || displayNameDraft == identity.displayName)

      HStack {
        Button("この端末からログアウト") {
          Task { await signOut() }
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
      }
    }
    .font(.caption)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
  }

  private func authenticatedSessionView(email: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("ログイン済み・同期を再試行してください", systemImage: "person.crop.circle.badge.exclamationmark")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
      Text(email)
        .font(.caption)
      HStack {
        Button("アカウント情報を再同期") {
          Task { await loadBusinessIdentity() }
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)

        Button("ログアウト", role: .destructive) {
          Task { await signOut() }
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
  }

  @MainActor
  private func requestOTP() async {
    guard let service = makeAuthService() else {
      setMessage(authenticationConfigurationMessage, error: true)
      return
    }
    let normalizedEmail = EmailOTPInput.normalizedEmail(email)
    let isResend = isOTPRequested
    isWorking = true
    defer { isWorking = false }
    do {
      try await service.sendEmailOTP(to: normalizedEmail)
      auth = service
      email = normalizedEmail
      lastEmail = normalizedEmail
      requestedEmail = normalizedEmail
      isOTPRequested = true
      otp = ""
      let note = isResend ? "以前のメールのコードは使えません。" : ""
      setMessage("\(normalizedEmail) に確認コードを送信しました。\(note)最新のメールの数字コードを入力してください。", error: false)
    } catch {
      setMessage("コードを送信できませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func verifyOTP() async {
    // Verify against the client and address that requested the code. A different
    // address or project never matches the code and is reported as otp_expired.
    guard let service = auth, let targetEmail = requestedEmail else {
      setMessage("確認コードを送信してから入力してください。", error: true)
      return
    }
    let code = EmailOTPInput.normalizedCode(otp)
    guard EmailOTPInput.isPlausibleCode(code) else {
      setMessage("メールに記載された数字コードをすべて入力してください。", error: true)
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let hasSession = try await service.verifyEmailOTP(email: targetEmail, code: code)
      guard hasSession else {
        setMessage(
          "確認コードは受理されましたが、ログインセッションが発行されませんでした。確認コードを再送してもう一度ログインしてください。",
          error: true
        )
        return
      }
    } catch {
      setMessage("確認コードを検証できませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
      return
    }
    auth = service
    authenticatedEmail = targetEmail
    lastEmail = targetEmail
    resetOTPRequest()
    do {
      try await loadBusinessIdentity(using: service)
    } catch {
      setMessage(
        "ログインしましたが、業務User取得に失敗しました: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func restoreSessionIfPresent() async {
    guard let service = configuredAuthService(), service.client.auth.currentSession != nil else {
      return
    }
    auth = service
    do {
      let session = try await service.client.auth.session
      authenticatedEmail = session.user.email
      if email.isEmpty, let sessionEmail = session.user.email {
        email = sessionEmail
        lastEmail = sessionEmail
      }
    } catch {
      setMessage(
        "保存済みのSupabaseログインを確認できませんでした: \(AuthenticationErrorMessage.describe(error))",
        error: true
      )
      return
    }
    do {
      let didSync = try await AuthenticatedAPISyncFlow.run(
        isAuthenticated: allowsAutomaticAPISync
      ) {
        try await loadBusinessIdentity(using: service, origin: .automaticSessionRestore)
      }
      if !didSync {
        setMessage(
          "保存済みのログインはありますが、サーバー同期は端末内利用中のため停止しています。",
          error: false
        )
      }
    } catch {
      setMessage(
        "Supabaseログインは保存されていますが、backendのEnsureUser／GetMeに失敗しました: \(AuthenticationErrorMessage.describe(error))",
        error: true
      )
    }
  }

  @MainActor
  private func loadBusinessIdentity() async {
    guard let service = auth ?? makeAuthService() else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await loadBusinessIdentity(using: service)
    } catch {
      setMessage("業務User取得に失敗しました: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func loadBusinessIdentity(
    using service: SupabaseAuthService,
    origin: IdentitySyncOrigin = .userInitiated
  ) async throws {
    let session = try await service.client.auth.session
    guard let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL else {
      throw SettingsInputError.invalidURL("Connect API URL")
    }
    let operationKey = "mobile.identity.ensureUser.operation.\(session.user.id.uuidString)"
    let defaults = UserDefaults.standard
    let operationID = (defaults.string(forKey: operationKey) ?? UUID().uuidString).lowercased()
    defaults.set(operationID, forKey: operationKey)

    let repository = IdentityAPIRepository(
      baseURL: try validatedURL(apiBaseURLText, label: "Connect API URL"), auth: service)
    var currentIdentity = try await repository.ensureUserAndFetchCurrentUser(
      operationID: operationID)
    defaults.removeObject(forKey: operationKey)
    if hasPendingAvatarChoice && currentIdentity.avatarID != avatarSelection {
      currentIdentity = try await repository.updateAvatar(avatarSelection)
    }
    hasPendingAvatarChoice = false
    identity = currentIdentity
    avatarSelection = currentIdentity.avatarID
    #if DEBUG
      setMessage("Supabase Auth、EnsureUser、GetMeを確認しました。", error: false)
    #else
      setMessage("ログインしました。", error: false)
    #endif
    if origin.notifiesRootAuthenticationState {
      onAuthenticationChanged()
    }
  }

  @MainActor
  private func saveDisplayName() async {
    guard let service = auth ?? makeAuthService(),
      let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL
    else {
      setMessage("表示名を保存できません。ログイン状態とAPI設定を確認してください。", error: true)
      return
    }
    let displayName = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !displayName.isEmpty, displayName.unicodeScalars.count <= 30 else {
      setMessage("表示名は前後の空白を除いて1〜30文字にしてください。", error: true)
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let repository = IdentityAPIRepository(
        baseURL: try validatedURL(apiBaseURLText, label: "Connect API URL"),
        auth: service
      )
      let updatedIdentity = try await repository.updateDisplayName(displayName)
      auth = service
      identity = updatedIdentity
      displayNameDraft = updatedIdentity.displayName
      onAuthenticationChanged()
      setMessage("表示名を保存しました。グループメンバーに表示されます。", error: false)
    } catch {
      setMessage("表示名を保存できませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func saveAvatar() async {
    guard let service = auth ?? makeAuthService(),
      let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL
    else {
      setMessage("アイコンを保存できません。ログイン状態とAPI設定を確認してください。", error: true)
      return
    }
    guard ProfileAvatar(rawValue: avatarSelection) != nil else {
      setMessage("このアイコンは選択できません。", error: true)
      return
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let repository = IdentityAPIRepository(
        baseURL: try validatedURL(apiBaseURLText, label: "Connect API URL"), auth: service)
      let updatedIdentity = try await repository.updateAvatar(avatarSelection)
      identity = updatedIdentity
      avatarSelection = updatedIdentity.avatarID
      hasPendingAvatarChoice = false
      isShowingAvatarPicker = false
      onAuthenticationChanged()
      setMessage("アイコンを保存しました。グループメンバーに表示されます。", error: false)
    } catch {
      setMessage("アイコンを保存できませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func signOut() async {
    guard let service = auth else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await service.signOutFromThisDevice()
      identity = nil
      auth = nil
      authenticatedEmail = nil
      resetOTPRequest()
      onAuthenticationChanged()
      setMessage("この端末からログアウトしました。", error: false)
    } catch {
      setMessage("ログアウトできませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
    }
  }

  @MainActor
  private func resetOTPRequest() {
    isOTPRequested = false
    requestedEmail = nil
    otp = ""
  }

  @MainActor
  private func makeAuthService() -> SupabaseAuthService? {
    MobileAppConfiguration.makeAuthService()
  }

  @MainActor
  private func configuredAuthService() -> SupabaseAuthService? {
    MobileAppConfiguration.makeAuthService()
  }

  private var hasConnectionConfiguration: Bool {
    MobileAppConfiguration.supabaseProjectURL != nil
      && MobileAppConfiguration.supabasePublishableKey != nil
      && MobileAppConfiguration.connectAPIBaseURL != nil
  }

  private var authenticationConfigurationMessage: String {
    #if DEBUG
      "Supabase Project URLと公開用publishable/anon keyを入力してください。"
    #else
      "アプリの接続設定を読み込めません。ReleaseのBuild Settingsを確認してください。"
    #endif
  }

  private func validatedURL(_ value: String, label: String) throws -> URL {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil
    else {
      throw SettingsInputError.invalidURL(label)
    }
    return url
  }

  @MainActor
  private func setMessage(_ value: String, error: Bool) {
    message = value
    isError = error
  }
}

private enum SettingsInputError: LocalizedError {
  case invalidURL(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL(let label): "\(label)を確認してください。"
    }
  }
}
