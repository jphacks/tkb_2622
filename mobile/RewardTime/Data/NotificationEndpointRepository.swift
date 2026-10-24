import Foundation
import Supabase

struct ConfiguredNotificationEndpointRepository {
    private struct RegisterRequest: Encodable {
        let apnsToken: String
        let environment: String
    }

    private struct RegisterResponse: Decodable {
        let registered: Bool
    }

    private struct DeleteResponse: Decodable {
        let deleted: Bool
    }

    func register(token: String, environment: String) async throws {
        let client = try makeClient()
        let apnsEnvironment = environment == "development" ? "AP_NS_ENVIRONMENT_DEVELOPMENT" : "AP_NS_ENVIRONMENT_PRODUCTION"
        let response: RegisterResponse = try await client.call(
            service: "identity.v1.IdentityService",
            method: "RegisterNotificationEndpoint",
            requestBody: RegisterRequest(apnsToken: token, environment: apnsEnvironment),
            responseType: RegisterResponse.self
        )
        guard response.registered else { throw NotificationEndpointError.registrationRejected }
    }

    func delete() async throws {
        let client = try makeClient()
        let response: DeleteResponse = try await client.call(
            service: "identity.v1.IdentityService",
            method: "DeleteNotificationEndpoint",
            requestBody: EmptyRequest(),
            responseType: DeleteResponse.self
        )
        guard response.deleted else { throw NotificationEndpointError.deletionRejected }
    }

    private func makeClient() throws -> ConnectJSONClient {
        let projectURLText = MobileAppConfiguration.supabaseProjectURL ?? ""
        let publishableKey = MobileAppConfiguration.supabasePublishableKey ?? ""
        let apiURLText = MobileAppConfiguration.connectAPIBaseURL ?? ""
        guard let projectURL = URL(string: projectURLText),
              let apiURL = URL(string: apiURLText),
              !publishableKey.isEmpty,
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret") else {
            throw NotificationEndpointError.missingConfiguration
        }
        let auth = SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        return ConnectJSONClient(baseURL: apiURL, tokenProvider: auth)
    }

    private struct EmptyRequest: Encodable {}
}

private enum NotificationEndpointError: LocalizedError {
    case missingConfiguration
    case registrationRejected
    case deletionRejected

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "通知APIの接続設定を確認してください。"
        case .registrationRejected: "サーバーが通知先登録を確認できませんでした。"
        case .deletionRejected: "サーバーが通知先解除を確認できませんでした。"
        }
    }
}
