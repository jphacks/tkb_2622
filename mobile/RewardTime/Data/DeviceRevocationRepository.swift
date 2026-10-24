import Foundation

enum DeviceSettingsRepositoryError: Error, LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    case deviceNotActive
    case deviceNotRevoked
    case policyConflict
    case requestFailed(operation: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "設定タブでSupabaseとAPIの接続情報を設定してください。"
        case .invalidConfiguration:
            return "Supabase URL・公開用キー・API URLを確認してください。"
        case .deviceNotActive:
            return "この端末の登録が無効です。端末管理で状態を確認してください。"
        case .deviceNotRevoked:
            return "この端末の登録を解除できませんでした。通信状態を確認して再試行してください。"
        case .policyConflict:
            return "制限設定が続けて更新されました。少し待ってからもう一度同期してください。"
        case .requestFailed(let operation, let underlying):
            let detail = (underlying as? LocalizedError)?.errorDescription
                ?? underlying.localizedDescription
            return "\(detail) (API: \(operation))"
        }
    }
}

struct ConfiguredDeviceRevocationRepository {
    private struct ListRequest: Encodable {
        let pageSize: Int
        let pageToken: String
    }

    private struct ListResponse: Decodable {
        let devices: [Device]?
        let nextPageToken: String?
    }

    private struct RevokeRequest: Encodable {
        let operationId: String
        let deviceId: String
        let expectedVersion: String
    }

    private struct RevokeResponse: Decodable {
        let device: Device
    }

    private struct DeleteEndpointRequest: Encodable {
        let registrationId: String
    }

    private struct DeleteEndpointResponse: Decodable {
        let deleted: Bool
    }

    private struct Device: Decodable {
        let id: String
        let status: String
        let version: ProtoJSONInt64
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func revokeRegisteredDevice(client: ConnectJSONClient) async throws {
        let deviceKey = "mobile.device.id"
        guard let registeredDeviceID = defaults.string(forKey: deviceKey),
              !registeredDeviceID.isEmpty else { return }

        if let pending = loadPendingRevocation() {
            do {
                try await revokeDevice(client: client, operationID: pending.operationID,
                                       deviceID: pending.deviceID, expectedVersion: pending.expectedVersion)
                try await deleteNotificationEndpoint(client: client)
                clearRegistration()
                return
            } catch ConnectJSONClient.ClientError.connect(code: "aborted") {
                clearPendingRevocation()
            }
        }

        var pageToken = ""
        while true {
            let response: ListResponse
            do {
                response = try await client.call(
                    service: "identity.v1.IdentityService",
                    method: "ListDevices",
                    requestBody: ListRequest(pageSize: 100, pageToken: pageToken),
                    responseType: ListResponse.self
                )
            } catch ConnectJSONClient.ClientError.connect(code: "permission_denied") {
                // A server-side revocation already disables ListDevices for this session.
                // Endpoint deletion is still permitted and keeps logout recoverable.
                try await deleteNotificationEndpoint(client: client)
                clearRegistration()
                return
            } catch {
                throw DeviceSettingsRepositoryError.requestFailed(
                    operation: "identity.v1.IdentityService/ListDevices",
                    underlying: error
                )
            }
            if let device = (response.devices ?? []).first(where: { $0.id == registeredDeviceID }) {
                if device.status == "ACTIVE" {
                    let operationID = UUID().uuidString.lowercased()
                    let expectedVersion = String(device.version.value)
                    savePendingRevocation(operationID: operationID, deviceID: device.id,
                                          expectedVersion: expectedVersion)
                    try await revokeDevice(client: client, operationID: operationID,
                                           deviceID: device.id, expectedVersion: expectedVersion)
                }
                try await deleteNotificationEndpoint(client: client)
                clearRegistration()
                return
            }
            guard let nextPageToken = response.nextPageToken, !nextPageToken.isEmpty else {
                try await deleteNotificationEndpoint(client: client)
                clearRegistration()
                return
            }
            pageToken = nextPageToken
        }
    }

    private func revokeDevice(client: ConnectJSONClient, operationID: String,
                              deviceID: String, expectedVersion: String) async throws {
        let revoked: RevokeResponse
        do {
            revoked = try await client.call(
                service: "identity.v1.IdentityService",
                method: "RevokeDevice",
                requestBody: RevokeRequest(operationId: operationID, deviceId: deviceID,
                                           expectedVersion: expectedVersion),
                responseType: RevokeResponse.self
            )
        } catch ConnectJSONClient.ClientError.connect(code: "aborted") {
            throw ConnectJSONClient.ClientError.connect(code: "aborted")
        } catch {
            throw DeviceSettingsRepositoryError.requestFailed(
                operation: "identity.v1.IdentityService/RevokeDevice",
                underlying: error
            )
        }
        guard revoked.device.status == "REVOKED" else {
            throw DeviceSettingsRepositoryError.requestFailed(
                operation: "identity.v1.IdentityService/RevokeDevice",
                underlying: DeviceSettingsRepositoryError.deviceNotRevoked
            )
        }
    }

    private func deleteNotificationEndpoint(client: ConnectJSONClient) async throws {
        guard let registrationID = defaults.string(forKey: "mobile.device.registrationID"),
              !registrationID.isEmpty else { return }
        let response: DeleteEndpointResponse
        do {
            response = try await client.call(
                service: "identity.v1.IdentityService",
                method: "DeleteNotificationEndpoint",
                requestBody: DeleteEndpointRequest(registrationId: registrationID),
                responseType: DeleteEndpointResponse.self
            )
        } catch {
            throw DeviceSettingsRepositoryError.requestFailed(
                operation: "identity.v1.IdentityService/DeleteNotificationEndpoint",
                underlying: error
            )
        }
        guard response.deleted else {
            throw DeviceSettingsRepositoryError.requestFailed(
                operation: "identity.v1.IdentityService/DeleteNotificationEndpoint",
                underlying: DeviceSettingsRepositoryError.deviceNotRevoked
            )
        }
    }

    private func clearRegistration() {
        defaults.removeObject(forKey: "mobile.device.id")
        defaults.removeObject(forKey: "mobile.device.registrationID")
        clearPendingRevocation()
    }

    private func savePendingRevocation(operationID: String, deviceID: String, expectedVersion: String) {
        defaults.set(operationID, forKey: "mobile.device.revoke.pendingOperationID")
        defaults.set(deviceID, forKey: "mobile.device.revoke.pendingDeviceID")
        defaults.set(expectedVersion, forKey: "mobile.device.revoke.pendingVersion")
    }

    private func loadPendingRevocation() -> (operationID: String, deviceID: String, expectedVersion: String)? {
        guard let operationID = defaults.string(forKey: "mobile.device.revoke.pendingOperationID"),
              let deviceID = defaults.string(forKey: "mobile.device.revoke.pendingDeviceID"),
              let expectedVersion = defaults.string(forKey: "mobile.device.revoke.pendingVersion"),
              !operationID.isEmpty, !deviceID.isEmpty, Int64(expectedVersion) != nil else {
            clearPendingRevocation()
            return nil
        }
        return (operationID, deviceID, expectedVersion)
    }

    private func clearPendingRevocation() {
        defaults.removeObject(forKey: "mobile.device.revoke.pendingOperationID")
        defaults.removeObject(forKey: "mobile.device.revoke.pendingDeviceID")
        defaults.removeObject(forKey: "mobile.device.revoke.pendingVersion")
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
