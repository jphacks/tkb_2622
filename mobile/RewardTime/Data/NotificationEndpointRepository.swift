import Foundation
import Supabase

struct ConfiguredNotificationEndpointRepository {
    private struct RegisterRequest: Encodable {
        let apnsToken: String
        let environment: String
        let registrationId: String
    }

    private struct RegisterResponse: Decodable {
        let registered: Bool
    }

    private struct DeleteResponse: Decodable {
        let deleted: Bool
    }

    private struct DeleteRequest: Encodable {
        let registrationId: String
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func register(token: String, environment: String) async throws {
        let client = try makeClient()
        try await register(token: token, environment: environment, client: client)
    }

    func register(token: String, environment: String, client: ConnectJSONClient) async throws {
        let apnsEnvironment = environment == "development" ? "AP_NS_ENVIRONMENT_DEVELOPMENT" : "AP_NS_ENVIRONMENT_PRODUCTION"
        let deviceSettings = ConfiguredDeviceSettingsRepository(defaults: defaults)
        let registrationID = deviceSettings.stableRegistrationID()
        try await NotificationEndpointRegistrationFlow.register(
            ensureDevice: {
                do {
                    _ = try await deviceSettings.ensureDeviceRegistered(client: client)
                } catch {
                    throw NotificationEndpointError.requestFailed(
                        operation: "identity.v1.IdentityService/RegisterDevice",
                        underlying: error
                    )
                }
            },
            registerEndpoint: {
                do {
                    let response: RegisterResponse = try await client.call(
                        service: "identity.v1.IdentityService",
                        method: "RegisterNotificationEndpoint",
                        requestBody: RegisterRequest(
                            apnsToken: token,
                            environment: apnsEnvironment,
                            registrationId: registrationID
                        ),
                        responseType: RegisterResponse.self
                    )
                    guard response.registered else {
                        throw NotificationEndpointError.registrationRejected
                    }
                } catch {
                    throw NotificationEndpointError.requestFailed(
                        operation: "identity.v1.IdentityService/RegisterNotificationEndpoint",
                        underlying: error
                    )
                }
            }
        )
    }

    func delete() async throws {
        let client = try makeClient()
        let registrationID = ConfiguredDeviceSettingsRepository(defaults: defaults).stableRegistrationID()
        do {
            let response: DeleteResponse = try await client.call(
                service: "identity.v1.IdentityService",
                method: "DeleteNotificationEndpoint",
                requestBody: DeleteRequest(registrationId: registrationID),
                responseType: DeleteResponse.self
            )
            guard response.deleted else { throw NotificationEndpointError.deletionRejected }
        } catch {
            throw NotificationEndpointError.requestFailed(
                operation: "identity.v1.IdentityService/DeleteNotificationEndpoint",
                underlying: error
            )
        }
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

}

private enum NotificationEndpointError: LocalizedError {
    case missingConfiguration
    case registrationRejected
    case deletionRejected
    case requestFailed(operation: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "通知APIの接続設定を確認してください。"
        case .registrationRejected: return "サーバーが通知先登録を確認できませんでした。"
        case .deletionRejected: return "サーバーが通知先解除を確認できませんでした。"
        case .requestFailed(let operation, let underlying):
            let detail = (underlying as? LocalizedError)?.errorDescription
                ?? underlying.localizedDescription
            return "\(detail) (API: \(operation))"
        }
    }
}
