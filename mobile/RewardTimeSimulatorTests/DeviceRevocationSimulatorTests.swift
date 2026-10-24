import Foundation
import XCTest
@testable import RewardTime

final class DeviceRevocationSimulatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DeviceRevocationSimulatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        DeviceRevocationURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRevokesRegisteredDeviceBeforeClearingItsID() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methodNames: [String] = []
        DeviceRevocationURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methodNames.append(method)
            let body: String
            switch method {
            case "ListDevices": body = #"{"devices":[{"id":"device-123","status":"ACTIVE","version":"4"}]}"#
            case "RevokeDevice": body = #"{"device":{"id":"device-123","status":"REVOKED","version":"5"}}"#
            default: body = #"{"deleted":true}"#
            }
            return (Self.response(for: request, status: 200), Data(body.utf8))
        }

        try await repository().revokeRegisteredDevice(client: client())

        XCTAssertEqual(methodNames, ["ListDevices", "RevokeDevice", "DeleteNotificationEndpoint"])
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testFailedRevocationPreservesDeviceIDAndPreventsLocalSignOut() async {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        DeviceRevocationURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            let status = method == "ListDevices" || method == "DeleteNotificationEndpoint" ? 200 : 500
            let body: String
            switch method {
            case "ListDevices": body = #"{"devices":[{"id":"device-123","status":"ACTIVE","version":"4"}]}"#
            case "DeleteNotificationEndpoint": body = #"{"deleted":true}"#
            default: body = #"{"code":"internal","message":"request failed"}"#
            }
            return (Self.response(for: request, status: status), Data(body.utf8))
        }
        var didSignOutLocally = false

        do {
            try await DeviceSignOutFlow.perform(
                revokeDevice: { try await repository().revokeRegisteredDevice(client: client()) },
                signOutLocally: { didSignOutLocally = true }
            )
            XCTFail("Expected device revocation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/RevokeDevice"))
            XCTAssertFalse(didSignOutLocally)
            XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-123")
            XCTAssertEqual(defaults.string(forKey: "mobile.device.registrationID"), "registration-123")
        }
    }

    func testReplaysSameRevocationOperationAfterEndpointCleanupFailure() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methods: [String] = []
        var operationIDs: [String] = []
        var failEndpointCleanupOnce = true
        DeviceRevocationURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            if method == "RevokeDevice",
               let body = self.requestBody(from: request),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let operationID = json["operationId"] as? String {
                operationIDs.append(operationID)
            }
            if method == "DeleteNotificationEndpoint", failEndpointCleanupOnce {
                failEndpointCleanupOnce = false
                return (Self.response(for: request, status: 500), Data(#"{"code":"internal"}"#.utf8))
            }
            let body: String
            switch method {
            case "ListDevices": body = #"{"devices":[{"id":"device-123","status":"ACTIVE","version":"4"}]}"#
            case "RevokeDevice": body = #"{"device":{"id":"device-123","status":"REVOKED","version":"5"}}"#
            default: body = #"{"deleted":true}"#
            }
            return (Self.response(for: request, status: 200), Data(body.utf8))
        }

        do {
            try await repository().revokeRegisteredDevice(client: client())
            XCTFail("Expected endpoint cleanup to fail once")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/DeleteNotificationEndpoint"))
        }

        try await repository().revokeRegisteredDevice(client: client())

        XCTAssertEqual(methods, ["ListDevices", "RevokeDevice", "DeleteNotificationEndpoint", "RevokeDevice", "DeleteNotificationEndpoint"])
        XCTAssertEqual(operationIDs.count, 2)
        XCTAssertEqual(operationIDs[0], operationIDs[1])
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testCleansUpEndpointWhenDeviceWasAlreadyRevokedOnServer() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methods: [String] = []
        DeviceRevocationURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            let status = method == "ListDevices" ? 403 : 200
            let body = method == "ListDevices"
                ? #"{"code":"permission_denied","message":"device revoked"}"#
                : #"{"deleted":true}"#
            return (Self.response(for: request, status: status), Data(body.utf8))
        }

        try await repository().revokeRegisteredDevice(client: client())

        XCTAssertEqual(methods, ["ListDevices", "DeleteNotificationEndpoint"])
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testMissingDeviceStillDeletesEndpointAndRetainsStateUntilCleanupSucceeds() async throws {
        defaults.set("stale-device-id", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methods: [String] = []
        var failEndpointCleanupOnce = true
        DeviceRevocationURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            if method == "DeleteNotificationEndpoint", failEndpointCleanupOnce {
                failEndpointCleanupOnce = false
                return (Self.response(for: request, status: 500), Data(#"{"code":"internal"}"#.utf8))
            }
            let body = method == "ListDevices"
                ? #"{"devices":[]}"#
                : #"{"deleted":true}"#
            return (Self.response(for: request, status: 200), Data(body.utf8))
        }
        var didSignOutLocally = false

        do {
            try await DeviceSignOutFlow.perform(
                revokeDevice: { try await repository().revokeRegisteredDevice(client: client()) },
                signOutLocally: { didSignOutLocally = true }
            )
            XCTFail("Expected endpoint cleanup to fail once")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/DeleteNotificationEndpoint"))
            XCTAssertFalse(didSignOutLocally)
            XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "stale-device-id")
            XCTAssertEqual(defaults.string(forKey: "mobile.device.registrationID"), "registration-123")
        }

        try await DeviceSignOutFlow.perform(
            revokeDevice: { try await repository().revokeRegisteredDevice(client: client()) },
            signOutLocally: { didSignOutLocally = true }
        )

        XCTAssertEqual(methods, ["ListDevices", "DeleteNotificationEndpoint", "ListDevices", "DeleteNotificationEndpoint"])
        XCTAssertTrue(didSignOutLocally)
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testListDevicesFailureIncludesFailingOperation() async {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        DeviceRevocationURLProtocol.handler = { request in
            return (Self.response(for: request, status: 500), Data(#"{"code":"internal"}"#.utf8))
        }

        do {
            try await repository().revokeRegisteredDevice(client: client())
            XCTFail("Expected device listing to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/ListDevices"))
        }
    }

    func testGroupConnectErrorsShowDistinctActionsInSimulatorTarget() {
        XCTAssertTrue(GroupAPIErrorMessage.describe(.connect(code: "unimplemented")).contains("グループAPIがありません"))
        XCTAssertTrue(GroupAPIErrorMessage.describe(.connect(code: "not_found")).contains("not_found"))
        XCTAssertTrue(GroupAPIErrorMessage.describe(.connect(code: "unauthenticated")).contains("再ログイン"))

        let actionError: Error = ConnectJSONClient.ClientError.connect(code: "unauthenticated")
        XCTAssertTrue(GroupAPIErrorMessage.describe(actionError).contains("再ログイン"))
    }

    func testAuthenticationEntryRequiresIdentitySyncAndShowsFirstLaunchWelcome() {
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: false,
                businessUserReady: false,
                loginDeferred: false
            ),
            .welcome
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: true,
                businessUserReady: false,
                loginDeferred: false
            ),
            .identitySyncRequired
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: true,
                businessUserReady: true,
                loginDeferred: false
            ),
            .authenticated
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: false,
                businessUserReady: false,
                loginDeferred: true
            ),
            .localOnly
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: false,
                businessUserReady: false,
                loginDeferred: false,
                sessionCheckFailed: true
            ),
            .identitySyncRequired
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: false,
                businessUserReady: false,
                loginDeferred: true,
                sessionCheckFailed: true
            ),
            .localOnly
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(
                hasValidSession: true,
                businessUserReady: false,
                loginDeferred: true
            ),
            .localOnly
        )
        XCTAssertFalse(
            AuthenticationEntryState.needsBusinessIdentitySync(
                currentState: .localOnly,
                loginDeferred: true
            )
        )
    }

    func testDeviceSettingsErrorMessageIncludesConnectCode() {
        let message = DeviceSettingsSyncErrorMessage.describe(
            ConnectJSONClient.ClientError.connect(code: "not_found")
        )

        XCTAssertTrue(message.contains("(not_found)"))
    }

    func testLocalOnlyStateSkipsAuthenticatedSettingsAndSessionRestoreRequests() async throws {
        var requestCount = 0

        let didRun = try await AuthenticatedAPISyncFlow.run(isAuthenticated: false) {
            requestCount += 1
        }

        XCTAssertFalse(didRun)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: false,
                permission: .allowed,
                token: "apns-token"
            ),
            .signInRequired
        )
    }

    func testNotificationTokenCallbackHonorsDeniedSystemPermission() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                permission: .denied,
                token: "apns-token"
            ),
            .remove
        )
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                permission: .allowed,
                token: "apns-token"
            ),
            .register(token: "apns-token")
        )
    }

    @MainActor
    func testGroupWorkStartPollingUsesActionableConnectErrorMessage() async throws {
        let repository = WorkStartFailureGroupRepository(
            group: try JSONDecoder().decode(
                MobileGroup.self,
                from: Data(#"{"id":"group-1","name":"test","members":[]}"#.utf8)
            )
        )
        let viewModel = GroupViewModel(repository: repository)

        await viewModel.load()
        await viewModel.refreshWorkStarts()

        XCTAssertTrue(viewModel.workStartError?.contains("再ログイン") == true)
    }

    func testAmbiguousReservationFailureRetainsRetryMetadataPolicy() {
        let ambiguous: Error = ConnectJSONClient.ClientError.httpStatus(502)
        let rejected: Error = ConnectJSONClient.ClientError.connect(code: "failed_precondition")

        XCTAssertFalse(UsageReservationFailurePolicy.shouldDiscardPendingOperation(after: ambiguous))
        XCTAssertTrue(UsageReservationFailurePolicy.shouldDiscardPendingOperation(after: rejected))
    }

    func testPendingReservationCanRetryWhenCommittedBalanceWasDebited() {
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 0,
                pendingOperationID: "operation-1",
                pendingSeconds: 600
            ),
            .allowed
        )
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 0,
                pendingOperationID: nil,
                pendingSeconds: 600
            ),
            .insufficientBalance
        )
    }

    @MainActor
    func testGroupRefreshFailureKeepsPreviouslyLoadedGroups() async throws {
        let repository = SimulatorGroupRepository(groups: [try group(id: "group-1")])
        let viewModel = GroupViewModel(repository: repository)

        await viewModel.load()
        repository.fetchGroupsError = ConnectJSONClient.ClientError.connect(code: "unavailable")
        await viewModel.load()

        guard case .loaded(let groups) = viewModel.state else {
            return XCTFail("A failed refresh should retain the last successful group list")
        }
        XCTAssertEqual(groups.map(\.id), ["group-1"])
        XCTAssertNotNil(viewModel.loadError)

        repository.fetchGroupsError = nil
        repository.groups.append(try group(id: "group-2"))
        await viewModel.load()
        guard case .loaded(let refreshedGroups) = viewModel.state else {
            return XCTFail("A successful retry should replace the retained group list")
        }
        XCTAssertEqual(Set(refreshedGroups.map(\.id)), ["group-1", "group-2"])
        XCTAssertNil(viewModel.loadError)
    }

    private func group(id: String) throws -> MobileGroup {
        try JSONDecoder().decode(
            MobileGroup.self,
            from: Data("{\"id\":\"\(id)\",\"name\":\"Study\",\"members\":[]}".utf8)
        )
    }

    private func repository() -> ConfiguredDeviceRevocationRepository {
        ConfiguredDeviceRevocationRepository(defaults: defaults)
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceRevocationURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: SimulatorTestTokenProvider()
        )
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
private final class SimulatorGroupRepository: GroupRepository {
    var groups: [MobileGroup]
    var fetchGroupsError: Error?

    init(groups: [MobileGroup]) {
        self.groups = groups
    }

    func fetchGroups() async throws -> [MobileGroup] {
        if let fetchGroupsError { throw fetchGroupsError }
        return groups
    }

    func fetchWorkStarts() async throws -> [MobileGroupWorkStart] { [] }
    func createGroup(name: String, operationID: String) async throws -> MobileGroup { groups[0] }
    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation {
        fatalError("Not used by this test")
    }
    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup { groups[0] }
    func leaveGroup(groupID: String, operationID: String) async throws -> Bool { false }
}

private struct SimulatorTestTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-access-token" }
}

private struct WorkStartFailureGroupRepository: GroupRepository {
    let group: MobileGroup

    func fetchGroups() async throws -> [MobileGroup] { [group] }
    func fetchWorkStarts() async throws -> [MobileGroupWorkStart] {
        throw ConnectJSONClient.ClientError.connect(code: "unauthenticated")
    }
    func createGroup(name: String, operationID: String) async throws -> MobileGroup { group }
    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation {
        throw ConnectJSONClient.ClientError.connect(code: "unimplemented")
    }
    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup {
        group
    }
    func leaveGroup(groupID: String, operationID: String) async throws -> Bool { false }
}

private final class DeviceRevocationURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    private static var storedHandler: Handler?

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return storedHandler }
        set { lock.lock(); defer { lock.unlock() }; storedHandler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.storedHandler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
