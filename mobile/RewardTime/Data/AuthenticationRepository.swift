import Foundation
import Supabase

extension Notification.Name {
  static let mobileAuthenticationChanged = Notification.Name("mobile.authentication.changed")
  static let mobileAPNsTokenReceived = Notification.Name("mobile.apns.token.received")
  static let mobileAPNsRegistrationFailed = Notification.Name("mobile.apns.registration.failed")
}

enum MobileAppConfiguration {
  static var supabaseProjectURL: String? {
    configuredURL(
      value(userDefaultsKey: "mobile.supabase.projectURL", infoKey: "SUPABASE_PROJECT_URL"))
  }

  static var supabasePublishableKey: String? {
    value(userDefaultsKey: "mobile.supabase.publishableKey", infoKey: "SUPABASE_PUBLISHABLE_KEY")
  }

  static var connectAPIBaseURL: String? {
    configuredURL(value(userDefaultsKey: "mobile.api.baseURL", infoKey: "CONNECT_API_BASE_URL"))
  }

  @MainActor
  static func makeAuthService() -> SupabaseAuthService? {
    guard let projectURLText = supabaseProjectURL,
      let publishableKey = supabasePublishableKey,
      let projectURL = URL(string: projectURLText),
      ["http", "https"].contains(projectURL.scheme?.lowercased() ?? ""),
      projectURL.host != nil,
      !publishableKey.localizedCaseInsensitiveContains("service_role"),
      !publishableKey.localizedCaseInsensitiveContains("secret")
    else {
      return nil
    }
    return SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
  }

  private static func value(userDefaultsKey: String, infoKey: String) -> String? {
    #if DEBUG
      if let storedValue = configuredValue(UserDefaults.standard.string(forKey: userDefaultsKey)) {
        return storedValue
      }
      if infoKey == "CONNECT_API_BASE_URL" {
        return "http://127.0.0.1:8080"
      }
    #endif
    return configuredValue(Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
  }

  private static func configuredValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
    return trimmed
  }

  private static func configuredURL(_ value: String?) -> String? {
    guard let value else { return nil }
    #if DEBUG
      return value
    #else
      guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil
      else {
        return nil
      }
      return value
    #endif
  }
}

struct SupabaseAuthService: AccessTokenProviding {
  let client: SupabaseClient

  var authenticatedUserID: String? {
    client.auth.currentUser?.id.uuidString.lowercased()
  }

  init(projectURL: URL, publishableKey: String) {
    client = SupabaseClientCache.shared.client(
      projectURL: projectURL,
      publishableKey: publishableKey
    )
  }

  init(client: SupabaseClient) {
    self.client = client
  }

  func sendEmailOTP(to email: String) async throws {
    try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
  }

  func verifyEmailOTP(email: String, code: String) async throws {
    // `.email` matches both the signup confirmation code (first login) and the
    // magic-link code (existing user), so a single request covers both cases.
    _ = try await client.auth.verifyOTP(email: email, token: code, type: .email)
  }

  func accessToken() async throws -> String? {
    do {
      return try await client.auth.session.accessToken
    } catch AuthError.sessionMissing {
      return nil
    }
  }

  func signOutFromThisDevice() async throws {
    try await DeviceSignOutFlow.perform(
      revokeDevice: {
        guard UserDefaults.standard.string(forKey: "mobile.device.id") != nil else { return }
        guard let apiURLText = MobileAppConfiguration.connectAPIBaseURL,
              let apiURL = URL(string: apiURLText), apiURL.host != nil else {
          throw DeviceSettingsRepositoryError.missingConfiguration
        }
        let api = ConnectJSONClient(baseURL: apiURL, tokenProvider: self)
        try await ConfiguredDeviceRevocationRepository().revokeRegisteredDevice(client: api)
      },
      signOutLocally: {
        try await client.auth.signOut(scope: .local)
      }
    )
  }
}

private final class SupabaseClientCache: @unchecked Sendable {
  private struct Key: Hashable {
    let projectURL: URL
    let publishableKey: String
  }

  static let shared = SupabaseClientCache()

  private let lock = NSLock()
  private var clients: [Key: SupabaseClient] = [:]

  func client(projectURL: URL, publishableKey: String) -> SupabaseClient {
    let key = Key(projectURL: projectURL, publishableKey: publishableKey)
    lock.lock()
    defer { lock.unlock() }

    if let client = clients[key] {
      return client
    }

    let client = SupabaseClient(
      supabaseURL: projectURL,
      supabaseKey: publishableKey,
      options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
      )
    )
    clients[key] = client
    return client
  }
}

enum EmailOTPInput {
  static func normalizedEmail(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// Keeps ASCII digits only, so pasted or autofilled codes with spaces or
  /// full-width digits still match the code Supabase sent.
  static func normalizedCode(_ raw: String) -> String {
    let halfWidth = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
    return String(halfWidth.filter { $0.isASCII && $0.isNumber })
  }

  static func isPlausibleCode(_ code: String) -> Bool {
    (6...10).contains(code.count)
  }
}

enum AuthenticationErrorMessage {
  static func describe(_ error: Error) -> String {
    guard let authError = error as? AuthError else {
      return error.localizedDescription
    }
    switch authError.errorCode {
    case .otpExpired:
      return "確認コードが無効か期限切れです。最後に届いたメールのコードを入力するか、コードを再送してください。(otp_expired)"
    case .overEmailSendRateLimit, .overRequestRateLimit:
      return "送信・認証の回数制限に達しました。しばらく待ってから再試行してください。(\(authError.errorCode.rawValue))"
    default:
      return "\(authError.message) (\(authError.errorCode.rawValue))"
    }
  }
}

struct MobileIdentity: Decodable {
  let id: String
  let status: String
  let createdAt: String
  let displayName: String
  let avatarID: String

  private enum CodingKeys: String, CodingKey {
    case id, status, createdAt, displayName
    case avatarID = "avatarId"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    status = try container.decode(String.self, forKey: .status)
    createdAt = try container.decode(String.self, forKey: .createdAt)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "メンバー"
    avatarID = try container.decodeIfPresent(String.self, forKey: .avatarID) ?? ProfileAvatar.defaultAvatar.rawValue
  }
}

struct EnsureUserRequest: Encodable {
  let operationId: String
}

struct UpdateDisplayNameRequest: Encodable {
  let displayName: String
}

struct UpdateAvatarRequest: Encodable {
  let avatarID: String

  private enum CodingKeys: String, CodingKey { case avatarID = "avatarId" }
}

struct EmptyIdentityRequest: Encodable {}

private struct EnsureUserResponse: Decodable {
  let user: MobileIdentity
}

private struct GetMeResponse: Decodable {
  let user: MobileIdentity
}

private struct UpdateDisplayNameResponse: Decodable {
  let user: MobileIdentity
}

private struct UpdateAvatarResponse: Decodable {
  let user: MobileIdentity
}

struct IdentityAPIRepository {
  private let client: ConnectJSONClient

  init(baseURL: URL, auth: SupabaseAuthService) {
    client = ConnectJSONClient(baseURL: baseURL, tokenProvider: auth)
  }

  init(client: ConnectJSONClient) {
    self.client = client
  }

  func ensureUserAndFetchCurrentUser(operationID: String) async throws -> MobileIdentity {
    let _: EnsureUserResponse = try await client.call(
      service: "identity.v1.IdentityService",
      method: "EnsureUser",
      requestBody: EnsureUserRequest(operationId: operationID),
      responseType: EnsureUserResponse.self
    )

    let response: GetMeResponse = try await client.call(
      service: "identity.v1.IdentityService",
      method: "GetMe",
      requestBody: EmptyIdentityRequest(),
      responseType: GetMeResponse.self
    )
    return response.user
  }

  func updateDisplayName(_ displayName: String) async throws -> MobileIdentity {
    let response: UpdateDisplayNameResponse = try await client.call(
      service: "identity.v1.IdentityService",
      method: "UpdateDisplayName",
      requestBody: UpdateDisplayNameRequest(displayName: displayName),
      responseType: UpdateDisplayNameResponse.self
    )
    return response.user
  }

  func updateAvatar(_ avatarID: String) async throws -> MobileIdentity {
    let response: UpdateAvatarResponse = try await client.call(
      service: "identity.v1.IdentityService",
      method: "UpdateAvatar",
      requestBody: UpdateAvatarRequest(avatarID: avatarID),
      responseType: UpdateAvatarResponse.self
    )
    return response.user
  }
}
