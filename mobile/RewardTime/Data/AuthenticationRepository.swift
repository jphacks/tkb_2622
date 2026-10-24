import Foundation
import Supabase

struct SupabaseAuthService: AccessTokenProviding {
    let client: SupabaseClient

    init(projectURL: URL, publishableKey: String) {
        client = SupabaseClient(supabaseURL: projectURL, supabaseKey: publishableKey)
    }

    func sendEmailOTP(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    func verifyEmailOTP(email: String, code: String) async throws {
        do {
            // A first-time user with email confirmation enabled receives a signup OTP.
            _ = try await client.auth.verifyOTP(email: email, token: code, type: .signup)
        } catch {
            // Existing passwordless users receive the regular email OTP type.
            _ = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        }
    }

    func accessToken() async throws -> String? {
        try await client.auth.session.accessToken
    }

    func signOutFromThisDevice() async throws {
        try await client.auth.signOut(scope: .local)
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
