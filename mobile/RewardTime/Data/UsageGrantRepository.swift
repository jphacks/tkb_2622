import Foundation

struct UsageGrantSnapshot {
    let id: String
    let reservedSeconds: Int64
    let reportedSeconds: Int64
    let status: String
    let controlRevision: Int64
    let isSettled: Bool
}

struct UsageGrantReservationResult {
    let grant: UsageGrantSnapshot
    let deviceID: String
    let controlRevision: Int64
    let desiredMode: String
}

struct UsageGrantSyncResult {
    let grant: UsageGrantSnapshot
    let measuredSeconds: Int
}

struct ConfiguredUsageGrantRepository {
    private struct PendingUsageReport: Codable {
        let operationID: String
        let sequence: Int64
        let cumulativeSeconds: Int64
        let observedAt: Date
        let isFinal: Bool
    }
    private struct ReserveRequest: Encodable {
        let operationId: String
        let sessionId: String
        let expectedSessionVersion: String
        let deviceId: String
        let requestedSeconds: String
    }

    private struct ReserveResponse: Decodable {
        let grant: GrantDTO
        let state: RestrictionStateDTO
    }

    private struct GrantResponse: Decodable {
        let grant: GrantDTO
    }

    private struct GrantDTO: Decodable {
        let id: String
        let reservedSeconds: ProtoJSONInt64
        let reportedSeconds: ProtoJSONInt64?
        let status: String
        let controlRevision: ProtoJSONInt64
        let consumedSeconds: ProtoJSONInt64?
    }

    private struct RestrictionStateDTO: Decodable {
        let deviceId: String
        let controlRevision: ProtoJSONInt64
        let desiredMode: String
    }

    private struct ReportStateRequest: Encodable {
        let operationId: String
        let deviceId: String
        let controlRevision: String
        let grantId: String
        let shieldStatus: String
        let appliedAt: String
        let permissionStatus: String
        let failureReason: String
    }

    private struct ReportStateResponse: Decodable {
        let applied: Bool
    }

    private struct ReportUsageRequest: Encodable {
        let operationId: String
        let grantId: String
        let reportSeq: String
        let cumulativeSeconds: String
        let observedAt: String
        let final: Bool
    }

    private struct ReportUsageResponse: Decodable {
        let grant: GrantDTO
    }

    private struct GetGrantRequest: Encodable {
        let grantId: String
    }

    private struct GetOperationRequest: Encodable {
        let kind: String
        let operationId: String
    }

    private struct GetOperationResponse: Decodable {
        let status: String
        let resourceId: String
    }

    private let client: ConnectJSONClient
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) throws {
        let projectURLText = MobileAppConfiguration.supabaseProjectURL ?? ""
        let publishableKey = MobileAppConfiguration.supabasePublishableKey ?? ""
        let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL ?? ""
        guard let projectURL = Self.validatedURL(projectURLText),
              !publishableKey.isEmpty,
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret"),
              let apiBaseURL = Self.validatedURL(apiBaseURLText) else {
            throw UsageGrantRepositoryError.invalidConfiguration
        }
        self.defaults = defaults
        client = ConnectJSONClient(
            baseURL: apiBaseURL,
            tokenProvider: SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        )
    }

    func reserve(
        operationID: String,
        sessionID: String,
        expectedSessionVersion: Int64,
        requestedSeconds: Int64
    ) async throws -> UsageGrantReservationResult {
        guard let deviceID = defaults.string(forKey: "mobile.device.id"), !deviceID.isEmpty else {
            throw UsageGrantRepositoryError.deviceNotRegistered
        }
        let response: ReserveResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "ReserveUsageGrant",
            requestBody: ReserveRequest(
                operationId: operationID,
                sessionId: sessionID,
                expectedSessionVersion: String(expectedSessionVersion),
                deviceId: deviceID,
                requestedSeconds: String(requestedSeconds)
            ),
            responseType: ReserveResponse.self
        )
        return UsageGrantReservationResult(
            grant: Self.snapshot(response.grant),
            deviceID: response.state.deviceId,
            controlRevision: response.state.controlRevision.value,
            desiredMode: response.state.desiredMode
        )
    }

    func reportActivation(
        operationID: String = UUID().uuidString.lowercased(),
        deviceID: String,
        grantID: String,
        controlRevision: Int64,
        shieldStatus: String,
        appliedAt: Date = Date()
    ) async throws {
        try await reportRestrictionState(
            operationID: operationID,
            deviceID: deviceID,
            controlRevision: controlRevision,
            grantID: grantID,
            shieldStatus: shieldStatus,
            permissionStatus: "PERMISSION_STATUS_GRANTED",
            appliedAt: appliedAt
        )
    }

    func reportRestrictionState(
        operationID: String = UUID().uuidString.lowercased(),
        deviceID: String,
        controlRevision: Int64,
        grantID: String = "",
        shieldStatus: String,
        permissionStatus: String,
        failureReason: String = "",
        appliedAt: Date = Date()
    ) async throws {
        let _: ReportStateResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "ReportRestrictionState",
            requestBody: ReportStateRequest(
                operationId: operationID,
                deviceId: deviceID,
                controlRevision: String(controlRevision),
                grantId: grantID,
                shieldStatus: shieldStatus,
                appliedAt: Self.timestamp(appliedAt),
                permissionStatus: permissionStatus,
                failureReason: failureReason
            ),
            responseType: ReportStateResponse.self
        )
    }

    func getGrant(grantID: String) async throws -> UsageGrantSnapshot {
        let response: GrantResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "GetUsageGrant",
            requestBody: GetGrantRequest(grantId: grantID),
            responseType: GrantResponse.self
        )
        return Self.snapshot(response.grant)
    }

    func synchronizeActiveGrant(grantID: String) async throws -> UsageGrantSyncResult {
        let shared = ScreenTimeSharedStorage.defaults
        let measuredSeconds = max(0, shared.integer(forKey: "mobile.usage.measuredSeconds"))
        var grant = try await getGrant(grantID: grantID)

        if let deviceID = shared.string(forKey: "mobile.usage.deviceID"),
           let revisionText = shared.string(forKey: "mobile.usage.controlRevision"),
           let revision = Int64(revisionText) {
            let measured = min(Int64(measuredSeconds), grant.reservedSeconds)
            let localStatus = shared.string(forKey: "mobile.usage.localShieldStatus")
            let shouldShield = localStatus == "SHIELD_STATUS_SHIELDED"
                || measured >= grant.reservedSeconds
                || shared.string(forKey: "mobile.usage.completedGrantID") == grantID
                || shared.bool(forKey: "mobile.usage.monitorIntervalEnded")
            let shieldStatus = localStatus == "SHIELD_STATUS_ERROR"
                ? "SHIELD_STATUS_ERROR"
                : (shouldShield ? "SHIELD_STATUS_SHIELDED" : "SHIELD_STATUS_UNSHIELDED")
            let reportedGrantID = ["SHIELD_STATUS_UNSHIELDED", "SHIELD_STATUS_ERROR"].contains(shieldStatus) ? grantID : ""
            let stateKey = "mobile.usage.lastReportedStateFingerprint.\(grantID).\(revision)"
            let requestFingerprint = [
                deviceID,
                String(revision),
                reportedGrantID,
                shieldStatus,
                "PERMISSION_STATUS_GRANTED",
                ""
            ].joined(separator: "\u{1f}")
            if shared.string(forKey: stateKey) != requestFingerprint {
                let operationKey = "mobile.usage.stateReportOperationID.\(grantID).\(revision).\(shieldStatus)"
                let appliedAtKey = "\(operationKey).appliedAt"
                let fingerprintKey = "\(operationKey).requestFingerprint"
                let hasMatchingPendingRequest = shared.string(forKey: fingerprintKey) == requestFingerprint
                    && shared.object(forKey: appliedAtKey) as? Date != nil
                let operationID: String
                let appliedAt: Date
                if hasMatchingPendingRequest,
                   let pendingOperationID = shared.string(forKey: operationKey),
                   let pendingAppliedAt = shared.object(forKey: appliedAtKey) as? Date {
                    operationID = pendingOperationID
                    appliedAt = pendingAppliedAt
                } else {
                    operationID = UUID().uuidString.lowercased()
                    appliedAt = Date()
                    shared.set(operationID, forKey: operationKey)
                    shared.set(appliedAt, forKey: appliedAtKey)
                    shared.set(requestFingerprint, forKey: fingerprintKey)
                }
                try await reportActivation(
                    operationID: operationID,
                    deviceID: deviceID,
                    grantID: reportedGrantID,
                    controlRevision: revision,
                    shieldStatus: shieldStatus,
                    appliedAt: appliedAt
                )
                shared.set(requestFingerprint, forKey: stateKey)
                shared.removeObject(forKey: operationKey)
                shared.removeObject(forKey: appliedAtKey)
                shared.removeObject(forKey: fingerprintKey)
            }
        }

        for _ in 0..<2 {
            let pending = try loadPendingUsageReport(grantID: grantID)
            let cumulativeSeconds = min(Int64(measuredSeconds), grant.reservedSeconds)
            let isFinal = grant.status == "GRANT_STATUS_REVOKED" && !grant.isSettled
            guard pending != nil || cumulativeSeconds > grant.reportedSeconds || isFinal else { break }
            let report = pending ?? makePendingUsageReport(
                grantID: grantID,
                previousSeconds: grant.reportedSeconds,
                cumulativeSeconds: cumulativeSeconds,
                observedAt: shared.object(forKey: "mobile.usage.measuredAt") as? Date ?? Date(),
                isFinal: isFinal
            )
            try savePendingUsageReport(report, grantID: grantID)
            grant = try await reportUsage(
                operationID: report.operationID,
                grantID: grantID,
                reportSequence: report.sequence,
                cumulativeSeconds: report.cumulativeSeconds,
                observedAt: report.observedAt,
                final: report.isFinal
            )
            finishPendingUsageReport(report, grantID: grantID)
        }

        if grant.status == "GRANT_STATUS_EXHAUSTED"
            || (grant.status == "GRANT_STATUS_REVOKED" && grant.isSettled) {
            DeviceActivityUsageMonitor().stop()
        }
        let serverReportedSeconds = Int(min(grant.reportedSeconds, grant.reservedSeconds))
        return UsageGrantSyncResult(
            grant: grant,
            measuredSeconds: max(measuredSeconds, serverReportedSeconds)
        )
    }

    func synchronizeStoredActiveGrantIfPresent() async {
        guard let grantID = ScreenTimeSharedStorage.defaults.string(forKey: "mobile.usage.activeGrantID"),
              !grantID.isEmpty else { return }
        _ = try? await synchronizeActiveGrant(grantID: grantID)
    }

    func reportUsage(
        operationID: String,
        grantID: String,
        reportSequence: Int64,
        cumulativeSeconds: Int64,
        observedAt: Date,
        final: Bool
    ) async throws -> UsageGrantSnapshot {
        let response: ReportUsageResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "ReportUsage",
            requestBody: ReportUsageRequest(
                operationId: operationID,
                grantId: grantID,
                reportSeq: String(reportSequence),
                cumulativeSeconds: String(cumulativeSeconds),
                observedAt: Self.timestamp(observedAt),
                final: final
            ),
            responseType: ReportUsageResponse.self
        )
        return Self.snapshot(response.grant)
    }

    func reservationOperation(operationID: String) async throws -> String? {
        let response: GetOperationResponse = try await client.call(
            service: "restriction.v1.RestrictionService",
            method: "GetRestrictionOperation",
            requestBody: GetOperationRequest(kind: "OPERATION_KIND_RESERVE", operationId: operationID),
            responseType: GetOperationResponse.self
        )
        return response.status == "OPERATION_STATUS_SUCCEEDED" ? response.resourceId : nil
    }

    private static func snapshot(_ grant: GrantDTO) -> UsageGrantSnapshot {
        UsageGrantSnapshot(
            id: grant.id,
            reservedSeconds: grant.reservedSeconds.value,
            reportedSeconds: grant.reportedSeconds?.value ?? 0,
            status: grant.status,
            controlRevision: grant.controlRevision.value,
            isSettled: grant.consumedSeconds != nil
        )
    }

    private func makePendingUsageReport(
        grantID: String,
        previousSeconds: Int64,
        cumulativeSeconds: Int64,
        observedAt: Date,
        isFinal: Bool
    ) -> PendingUsageReport {
        let shared = ScreenTimeSharedStorage.defaults
        let savedSequence = Int64(shared.integer(forKey: "mobile.usage.reportSequence.\(grantID)"))
        return PendingUsageReport(
            operationID: UUID().uuidString.lowercased(),
            sequence: max(savedSequence + 1, previousSeconds / 60 + 1),
            cumulativeSeconds: max(previousSeconds, cumulativeSeconds),
            observedAt: observedAt,
            isFinal: isFinal
        )
    }

    private func loadPendingUsageReport(grantID: String) throws -> PendingUsageReport? {
        let key = "mobile.usage.pendingReport.\(grantID)"
        guard let data = ScreenTimeSharedStorage.defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(PendingUsageReport.self, from: data)
    }

    private func savePendingUsageReport(_ report: PendingUsageReport, grantID: String) throws {
        let data = try JSONEncoder().encode(report)
        ScreenTimeSharedStorage.defaults.set(data, forKey: "mobile.usage.pendingReport.\(grantID)")
    }

    private func finishPendingUsageReport(_ report: PendingUsageReport, grantID: String) {
        let shared = ScreenTimeSharedStorage.defaults
        shared.set(Int(report.sequence), forKey: "mobile.usage.reportSequence.\(grantID)")
        shared.removeObject(forKey: "mobile.usage.pendingReport.\(grantID)")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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

enum UsageGrantRepositoryError: Error, LocalizedError {
    case invalidConfiguration
    case deviceNotRegistered

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Supabaseとbackendの設定を確認してください。"
        case .deviceNotRegistered:
            "設定画面からiPhoneをbackendへ登録してください。"
        }
    }
}
