import FamilyControls
import Foundation

struct APIHomeRepository: HomeRepository {
    private struct EmptyRequest: Encodable {}

    private struct CurrentSessionResponse: Decodable {
        let session: SessionDTO?
    }

    private struct SessionDTO: Decodable {
        let id: String
        let status: String
        let version: ProtoJSONInt64?
        let minimumReached: Bool?
        let taskSnapshot: TaskSettingsDTO?
        let durations: DurationsDTO?
    }

    private struct TaskSettingsDTO: Decodable {
        let minimumSeconds: ProtoJSONInt64?
    }

    private struct DurationsDTO: Decodable {
        let activeMillis: ProtoJSONInt64?
    }

    private struct BalanceResponse: Decodable {
        let balance: BalanceDTO
    }

    private struct BalanceDTO: Decodable {
        let sessionId: String
        let balanceSeconds: ProtoJSONInt64

        private enum CodingKeys: String, CodingKey { case sessionId, balanceSeconds }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
            balanceSeconds = try container.decodeIfPresent(ProtoJSONInt64.self, forKey: .balanceSeconds)
                ?? ProtoJSONInt64(value: 0)
        }
    }

    private struct RestrictionStateResponse: Decodable {
        let state: RestrictionStateDTO
    }

    private struct RestrictionStateDTO: Decodable {
        let sessionId: String
        let deviceId: String
        let controlRevision: ProtoJSONInt64
        let desiredMode: String
        let appliedRevision: ProtoJSONInt64
        let shieldStatus: String
        let permissionStatus: String
        let activeGrant: UsageGrantDTO?

        private enum CodingKeys: String, CodingKey {
            case sessionId, deviceId, controlRevision, desiredMode, appliedRevision, shieldStatus, permissionStatus, activeGrant
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
            deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
            controlRevision = try container.decodeIfPresent(ProtoJSONInt64.self, forKey: .controlRevision)
                ?? ProtoJSONInt64(value: 0)
            desiredMode = try container.decodeIfPresent(String.self, forKey: .desiredMode)
                ?? "DESIRED_MODE_UNSPECIFIED"
            appliedRevision = try container.decodeIfPresent(ProtoJSONInt64.self, forKey: .appliedRevision)
                ?? ProtoJSONInt64(value: 0)
            shieldStatus = try container.decodeIfPresent(String.self, forKey: .shieldStatus)
                ?? "SHIELD_STATUS_UNSPECIFIED"
            permissionStatus = try container.decodeIfPresent(String.self, forKey: .permissionStatus)
                ?? "PERMISSION_STATUS_UNSPECIFIED"
            activeGrant = try container.decodeIfPresent(UsageGrantDTO.self, forKey: .activeGrant)
        }
    }

    private struct UsageGrantDTO: Decodable {
        let id: String
        let reservedSeconds: ProtoJSONInt64
        let status: String
    }

    private let client: ConnectJSONClient
    private let selectedApplicationCount: Int

    init(
        baseURL: URL,
        auth: any AccessTokenProviding,
        selectedApplicationCount: Int,
        session: URLSession = .shared
    ) {
        client = ConnectJSONClient(baseURL: baseURL, session: session, tokenProvider: auth)
        self.selectedApplicationCount = selectedApplicationCount
    }

    private func call<Request: Encodable, Response: Decodable>(
        service: String,
        method: String,
        requestBody: Request,
        responseType: Response.Type
    ) async throws -> Response {
        do {
            return try await client.call(
                service: service,
                method: method,
                requestBody: requestBody,
                responseType: responseType
            )
        } catch {
            throw APIHomeRepositoryError.requestFailed(
                operation: "\(service)/\(method)",
                underlying: error
            )
        }
    }

    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot {
        for attempt in 0..<2 {
            do {
                return try await fetchConsistentSnapshot()
            } catch APIHomeRepositoryError.inconsistentSessionIDs {
                guard attempt == 0 else {
                    throw APIHomeRepositoryError.inconsistentSessionIDs
                }
            }
        }
        throw APIHomeRepositoryError.inconsistentSessionIDs
    }

    private func fetchConsistentSnapshot() async throws -> MobileHomeSnapshot {
        async let sessionResponse: CurrentSessionResponse = call(
            service: "focus.v1.FocusService",
            method: "GetCurrentSession",
            requestBody: EmptyRequest(),
            responseType: CurrentSessionResponse.self
        )
        async let balanceResponse: BalanceResponse = call(
            service: "reward.v1.RewardService",
            method: "GetBalance",
            requestBody: EmptyRequest(),
            responseType: BalanceResponse.self
        )
        async let restrictionResponse: RestrictionStateResponse = call(
            service: "restriction.v1.RestrictionService",
            method: "GetRestrictionState",
            requestBody: EmptyRequest(),
            responseType: RestrictionStateResponse.self
        )

        let (session, balance, restriction) = try await (
            sessionResponse.session,
            balanceResponse.balance,
            restrictionResponse.state
        )

        try validateSessionIDs(
            currentSessionID: session?.id,
            balanceSessionID: balance.sessionId,
            restrictionSessionID: restriction.sessionId
        )

        let activeMillis = session?.durations?.activeMillis?.value ?? 0
        let minimumSeconds = session?.taskSnapshot?.minimumSeconds?.value
        let minimumProgress = minimumSeconds.map { minimum in
            minimum <= 0 ? 1 : min(Double(max(0, activeMillis)) / (Double(minimum) * 1_000), 1)
        }

        return MobileHomeSnapshot(
            sessionStatus: try sessionStatus(session?.status),
            elapsedMinutes: session.map {
                Int(max(0, ($0.durations?.activeMillis?.value ?? 0) / 60_000))
            },
            minimumSeconds: minimumSeconds.map { Int(max(0, $0)) },
            minimumProgress: minimumProgress,
            minimumReached: session?.minimumReached ?? false,
            rewardBalanceSeconds: Int(max(0, balance.balanceSeconds.value)),
            desiredRestriction: desiredRestrictionMode(restriction.desiredMode),
            restrictionStatus: appliedRestrictionStatus(restriction),
            restrictedApps: [],
            restrictedApplicationCount: selectedApplicationCount,
            lastSyncedAt: .now,
            isSampleData: false,
            sessionID: session?.id,
            sessionVersion: session?.version?.value,
            restrictionDeviceID: restriction.deviceId.isEmpty ? nil : restriction.deviceId,
            restrictionControlRevision: restriction.controlRevision.value,
            restrictionAppliedRevision: restriction.appliedRevision.value,
            restrictionShieldStatus: restriction.shieldStatus,
            restrictionPermissionStatus: restriction.permissionStatus,
            activeGrantID: restriction.activeGrant?.id,
            activeGrantReservedSeconds: restriction.activeGrant.map { Int($0.reservedSeconds.value) },
            activeGrantStatus: restriction.activeGrant?.status
        )
    }

    private func sessionStatus(_ status: String?) throws -> SessionStatus {
        guard let status else { return .noSession }
        switch status {
        case "SESSION_STATUS_RUNNING": return .working
        case "SESSION_STATUS_PAUSED": return .paused
        default: throw APIHomeRepositoryError.unexpectedSessionStatus
        }
    }

    private func desiredRestrictionMode(_ mode: String) -> DesiredRestrictionMode {
        switch mode {
        case "DESIRED_MODE_UNRESTRICTED": .unrestricted
        case "DESIRED_MODE_SHIELDED": .shielded
        case "DESIRED_MODE_TIMED_UNLOCK": .timedUnlock
        case "DESIRED_MODE_SESSION_ENDED": .sessionEnded
        default: .unknown
        }
    }

    private func appliedRestrictionStatus(_ state: RestrictionStateDTO) -> RestrictionStatus {
        guard state.appliedRevision.value >= state.controlRevision.value else {
            return .notConfirmed
        }
        if state.shieldStatus == "SHIELD_STATUS_ERROR" { return .failed }

        switch state.desiredMode {
        case "DESIRED_MODE_SHIELDED":
            return state.shieldStatus == "SHIELD_STATUS_SHIELDED" ? .restricted : .notConfirmed
        case "DESIRED_MODE_TIMED_UNLOCK":
            return state.shieldStatus == "SHIELD_STATUS_UNSHIELDED"
                ? .temporarilyReleased(endsAt: nil)
                : .notConfirmed
        case "DESIRED_MODE_UNRESTRICTED", "DESIRED_MODE_SESSION_ENDED":
            return state.shieldStatus == "SHIELD_STATUS_UNSHIELDED" ? .unrestricted : .notConfirmed
        default:
            return .notConfirmed
        }
    }

    private func validateSessionIDs(
        currentSessionID: String?,
        balanceSessionID: String,
        restrictionSessionID: String
    ) throws {
        let expectedSessionID = currentSessionID ?? ""
        guard balanceSessionID == expectedSessionID,
              restrictionSessionID == expectedSessionID else {
            throw APIHomeRepositoryError.inconsistentSessionIDs
        }
    }
}

private struct ProtoJSONInt64: Decodable {
    let value: Int64

    init(value: Int64) {
        self.value = value
    }

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

private enum APIHomeRepositoryError: LocalizedError {
    case inconsistentSessionIDs
    case unexpectedSessionStatus
    case requestFailed(operation: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .inconsistentSessionIDs:
            return "作業・残高・制限状態のセッションが一致しません。少し待ってから再読み込みしてください。 (API: GetCurrentSession/GetBalance/GetRestrictionState)"
        case .unexpectedSessionStatus:
            return "作業状態を読み取れませんでした。アプリを再読み込みしてください。 (API: focus.v1.FocusService/GetCurrentSession)"
        case .requestFailed(let operation, let underlying):
            let detail = (underlying as? LocalizedError)?.errorDescription
                ?? underlying.localizedDescription
            return "\(detail) (API: \(operation))"
        }
    }
}

struct ConfiguredHomeRepository: HomeRepository {
    func fetchCurrentSnapshot() async throws -> MobileHomeSnapshot {
        let defaults = ScreenTimeSharedStorage.defaults
        let projectURLText = MobileAppConfiguration.supabaseProjectURL ?? ""
        let publishableKey = MobileAppConfiguration.supabasePublishableKey ?? ""
        let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL ?? ""

        if projectURLText.isEmpty && publishableKey.isEmpty {
            throw HomeRepositoryConfigurationError.missingConfiguration
        }

        guard let projectURL = Self.validatedURL(projectURLText),
              !publishableKey.isEmpty,
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret"),
              let apiBaseURL = Self.validatedURL(apiBaseURLText) else {
            throw HomeRepositoryConfigurationError.invalidConfiguration
        }

        let auth = SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        let selectionData = defaults.data(forKey: "mobile.screenTime.selection")
        let selectedApplications = selectionData
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            .map(\.applicationTokens) ?? []
        let selectedApplicationCount = selectedApplications.count

        return try await APIHomeRepository(
            baseURL: apiBaseURL,
            auth: auth,
            selectedApplicationCount: selectedApplicationCount
        ).fetchCurrentSnapshot()
    }

    private static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

private enum HomeRepositoryConfigurationError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "設定タブでSupabase Project URL・公開用キー・API URLを設定し、ログインしてください。"
        case .invalidConfiguration:
            "設定タブのSupabase接続情報とAPI URLを確認してください。"
        }
    }
}
