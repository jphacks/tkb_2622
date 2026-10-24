import SwiftUI
import Supabase

struct AuthenticationSettingsSection: View {
    @AppStorage("mobile.supabase.projectURL") private var projectURLText = ""
    @AppStorage("mobile.supabase.publishableKey") private var publishableKey = ""
    @AppStorage("mobile.api.baseURL") private var apiBaseURLText = "http://127.0.0.1:8080"
    @AppStorage("mobile.auth.lastEmail") private var lastEmail = ""

    @State private var email = ""
    @State private var otp = ""
    @State private var isOTPRequested = false
    /// The address the latest code was sent to. Verification always uses this value.
    @State private var requestedEmail: String?
    @State private var isWorking = false
    @State private var auth: SupabaseAuthService?
    @State private var identity: MobileIdentity?
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        SurfaceCard {
            Label("アカウント接続", systemImage: "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.bold))

            Text("メールOTPでSupabase Authにログインし、業務UserのEnsureUserとGetMeを確認します。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)

            Group {
                TextField("Supabase Project URL", text: $projectURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("supabaseProjectURL")

                TextField("Supabase publishable key", text: $publishableKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("supabasePublishableKey")

                TextField("Connect API URL", text: $apiBaseURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("connectAPIBaseURL")
            }
            .textFieldStyle(.roundedBorder)
            .font(.footnote)

            Text("公開用キーだけを入力してください。service_role / secret keyは入力しないでください。実機ではAPI URLにMacのLAN IPを指定します。")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryInk)

            if let identity {
                identityView(identity)
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
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isOTPRequested {
                    TextField("メールに届いた確認コード", text: $otp)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("authOTP")

                    Button {
                        Task { await verifyOTP() }
                    } label: {
                        Label("ログインして業務Userを確認", systemImage: "checkmark.shield")
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
            Task { await restoreSessionIfPresent() }
        }
    }

    @ViewBuilder
    private func identityView(_ identity: MobileIdentity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("認証済み・業務User取得済み", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.teal)
            Text("User ID: \(identity.id)")
            Text("状態: \(identity.status)")
            Text("作成日時: \(identity.createdAt)")
            HStack {
                Button("業務Userを再取得") {
                    Task { await loadBusinessIdentity() }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

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

    @MainActor
    private func requestOTP() async {
        guard let service = makeAuthService() else {
            setMessage("Supabase Project URLと公開用publishable/anon keyを入力してください。", error: true)
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
            try await service.verifyEmailOTP(email: targetEmail, code: code)
        } catch {
            setMessage("確認コードを検証できませんでした: \(AuthenticationErrorMessage.describe(error))", error: true)
            return
        }
        lastEmail = targetEmail
        resetOTPRequest()
        do {
            try await loadBusinessIdentity(using: service)
        } catch {
            setMessage("ログインしましたが、業務User取得に失敗しました: \(AuthenticationErrorMessage.describe(error))", error: true)
        }
    }

    @MainActor
    private func restoreSessionIfPresent() async {
        guard let service = configuredAuthService(), service.client.auth.currentSession != nil else { return }
        auth = service
        do {
            let session = try await service.client.auth.session
            if email.isEmpty, let sessionEmail = session.user.email {
                email = sessionEmail
                lastEmail = sessionEmail
            }
            try await loadBusinessIdentity(using: service)
        } catch {
            setMessage("保存済みセッションを確認できませんでした。再ログインしてください。", error: true)
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
    private func loadBusinessIdentity(using service: SupabaseAuthService) async throws {
        let session = try await service.client.auth.session
        let operationKey = "mobile.identity.ensureUser.operation.\(session.user.id.uuidString)"
        let defaults = UserDefaults.standard
        let operationID = (defaults.string(forKey: operationKey) ?? UUID().uuidString).lowercased()
        defaults.set(operationID, forKey: operationKey)

        let repository = IdentityAPIRepository(baseURL: try validatedURL(apiBaseURLText, label: "Connect API URL"), auth: service)
        let currentIdentity = try await repository.ensureUserAndFetchCurrentUser(operationID: operationID)
        defaults.removeObject(forKey: operationKey)
        identity = currentIdentity
        setMessage("Supabase Auth、EnsureUser、GetMeを確認しました。", error: false)
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
            resetOTPRequest()
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
        configuredAuthService()
    }

    @MainActor
    private func configuredAuthService() -> SupabaseAuthService? {
        guard let projectURL = try? validatedURL(projectURLText, label: "Supabase Project URL"),
              !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret") else {
            return nil
        }
        return SupabaseAuthService(
            projectURL: projectURL,
            publishableKey: publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func validatedURL(_ value: String, label: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
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
