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
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "internal")
            XCTAssertFalse(didSignOutLocally)
            XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-123")
            XCTAssertEqual(defaults.string(forKey: "mobile.device.registrationID"), "registration-123")
        } catch {
            XCTFail("Unexpected error: \(error)")
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
        } catch ConnectJSONClient.ClientError.connect(code: "internal") {}

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
