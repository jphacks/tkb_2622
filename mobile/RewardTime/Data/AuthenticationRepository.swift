import Foundation
import Supabase

struct SupabaseAuthService: AccessTokenProviding {
    let client: SupabaseClient

    init(projectURL: URL, publishableKey: String) {
        client = SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
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
        try await client.auth.session.accessToken
    }

    func signOutFromThisDevice() async throws {
        try await client.auth.signOut(scope: .local)
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
}

struct EnsureUserRequest: Encodable {
    let operationId: String
}

struct EmptyIdentityRequest: Encodable {}

private struct EnsureUserResponse: Decodable {
    let user: MobileIdentity
}

private struct GetMeResponse: Decodable {
    let user: MobileIdentity
}

struct IdentityAPIRepository {
    private let client: ConnectJSONClient

    init(baseURL: URL, auth: SupabaseAuthService) {
        client = ConnectJSONClient(baseURL: baseURL, tokenProvider: auth)
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
}
