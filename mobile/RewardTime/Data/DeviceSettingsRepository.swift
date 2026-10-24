import Foundation
import UIKit

struct DeviceRestrictionSettings {
    let enabled: Bool
    let targetMode: String
    let configured: Bool
    let deviceConfigVersion: Int64
}

struct SyncedDevicePolicy {
    let deviceID: String
    let deviceName: String
    let policyVersion: Int64
    let policyStatus: String
}

struct ConfiguredDeviceSettingsRepository {
    private struct RegisterDeviceRequest: Encodable {
        let operationId: String
        let registrationId: String
        let platform: String
        let name: String
    }

    private struct RegisterDeviceResponse: Decodable {
        let device: DeviceDTO
    }

    private struct DeviceDTO: Decodable {
        let id: String
        let status: String
    }

    private struct GetPolicyRequest: Encodable {
        let deviceId: String
    }

    private struct GetPolicyResponse: Decodable {
        let policy: PolicyDTO
    }

    private struct PolicyDTO: Decodable {
        let deviceId: String
        let status: String
        let targetMode: String
        let deviceConfigVersion: ProtoJSONInt64
        let configured: Bool
        let version: ProtoJSONInt64

        var enabled: Bool {
            status == "POLICY_STATUS_ENABLED" || status == "POLICY_STATUS_PERMISSION_REQUIRED"
        }
    }

    private struct UpdatePolicyRequest: Encodable {
        let operationId: String
        let deviceId: String
        let expectedVersion: String
        let enabled: Bool
        let targetMode: String
        let deviceConfigVersion: String
        let configured: Bool
    }

    private struct UpdatePolicyResponse: Decodable {
        let policy: PolicyDTO
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func sync(settings: DeviceRestrictionSettings) async throws -> SyncedDevicePolicy {
        let projectURLText = defaults.string(forKey: "mobile.supabase.projectURL") ?? ""
        let publishableKey = defaults.string(forKey: "mobile.supabase.publishableKey") ?? ""
        let apiBaseURLText = defaults.string(forKey: "mobile.api.baseURL") ?? "http://127.0.0.1:8080"
        guard !projectURLText.isEmpty, !publishableKey.isEmpty else {
            throw DeviceSettingsRepositoryError.missingConfiguration
        }
        guard let projectURL = Self.validatedURL(projectURLText),
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret"),
              let apiBaseURL = Self.validatedURL(apiBaseURLText) else {
            throw DeviceSettingsRepositoryError.invalidConfiguration
        }

        let auth = SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        let client = ConnectJSONClient(baseURL: apiBaseURL, tokenProvider: auth)
        let registrationID = stableRegistrationID()
        let deviceName = await UIDevice.current.name
        let device = try await registerDevice(
            client: client,
            registrationID: registrationID,
            deviceName: deviceName
        )
        defaults.set(device.id, forKey: "mobile.device.id")

        let currentPolicy = try await currentPolicy(client: client, deviceID: device.id)
        if let currentPolicy,
           currentPolicy.targetMode == settings.targetMode,
           currentPolicy.enabled == settings.enabled,
           currentPolicy.configured == settings.configured,
           currentPolicy.deviceConfigVersion.value == settings.deviceConfigVersion {
            return SyncedDevicePolicy(
                deviceID: device.id,
                deviceName: deviceName,
                policyVersion: currentPolicy.version.value,
                policyStatus: currentPolicy.status
            )
        }

        let response: UpdatePolicyResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "UpdateRestrictionPolicy",
            requestBody: UpdatePolicyRequest(
                operationId: UUID().uuidString.lowercased(),
                deviceId: device.id,
                expectedVersion: String(currentPolicy?.version.value ?? 0),
                enabled: settings.enabled,
                targetMode: settings.targetMode,
                deviceConfigVersion: String(settings.deviceConfigVersion),
                configured: settings.configured
            ),
            responseType: UpdatePolicyResponse.self
        )
        return SyncedDevicePolicy(
            deviceID: response.policy.deviceId,
            deviceName: deviceName,
            policyVersion: response.policy.version.value,
            policyStatus: response.policy.status
        )
    }

    private func registerDevice(
        client: ConnectJSONClient,
        registrationID: String,
        deviceName: String
    ) async throws -> DeviceDTO {
        let key = "mobile.device.register.operation.\(registrationID)"
        let operationID = (defaults.string(forKey: key) ?? UUID().uuidString).lowercased()
        defaults.set(operationID, forKey: key)
        let response: RegisterDeviceResponse = try await client.call(
            service: "identity.v1.IdentityService",
            method: "RegisterDevice",
            requestBody: RegisterDeviceRequest(
                operationId: operationID,
                registrationId: registrationID,
                platform: "PLATFORM_IOS",
                name: deviceName
            ),
            responseType: RegisterDeviceResponse.self
        )
        defaults.removeObject(forKey: key)
        guard response.device.status == "ACTIVE" else {
            throw DeviceSettingsRepositoryError.deviceNotActive
        }
        return response.device
    }

    private func currentPolicy(client: ConnectJSONClient, deviceID: String) async throws -> PolicyDTO? {
        do {
            let response: GetPolicyResponse = try await client.call(
                service: "restriction.v1.RestrictionService",
                method: "GetRestrictionPolicy",
                requestBody: GetPolicyRequest(deviceId: deviceID),
                responseType: GetPolicyResponse.self
            )
            return response.policy
        } catch ConnectJSONClient.ClientError.connect(code: "not_found") {
            return nil
        }
    }

    private func stableRegistrationID() -> String {
        let key = "mobile.device.registrationID"
        if let stored = defaults.string(forKey: key) {
            let normalized = stored.lowercased()
            if normalized != stored { defaults.set(normalized, forKey: key) }
            return normalized
        }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }

    private static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

private struct ProtoJSONInt64: Decodable {
    let value: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let value = Int64(string) {
            self.value = value
        } else if let value = try? container.decode(Int64.self) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a protobuf JSON int64")
        }
    }
}

enum DeviceSettingsRepositoryError: Error {
    case missingConfiguration
    case invalidConfiguration
    case deviceNotActive
}

extension DeviceSettingsRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "設定タブでSupabaseとAPIの接続情報を設定してください。"
        case .invalidConfiguration:
            "Supabase URL・公開用キー・API URLを確認してください。"
        case .deviceNotActive:
            "この端末の登録が無効です。端末管理で状態を確認してください。"
        }
    }
}
