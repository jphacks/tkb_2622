import Foundation
import XCTest
@testable import ConnectJSONClient

final class DeviceRevocationRepositoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DeviceRevocationRepositoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        RevocationStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testListsDeviceThenRevokesItAndClearsStoredID() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var requests: [URLRequest] = []
        RevocationStubURLProtocol.handler = { request in
            requests.append(request)
            let responseBody: String
            if request.url?.path.hasSuffix("/ListDevices") == true {
                responseBody = #"{"devices":[{"id":"device-123","status":"ACTIVE","version":"4"}]}"#
            } else if request.url?.path.hasSuffix("/RevokeDevice") == true {
                responseBody = #"{"device":{"id":"device-123","status":"REVOKED","version":"5"}}"#
            } else {
                responseBody = #"{"deleted":true}"#
            }
            return (Self.response(for: request, status: 200), Data(responseBody.utf8))
        }

        try await repository().revokeRegisteredDevice(client: client())

        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["ListDevices", "RevokeDevice", "DeleteNotificationEndpoint"])
        let revokeBody = try XCTUnwrap(requestBody(from: requests[1]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: revokeBody) as? [String: Any])
        XCTAssertEqual(json["deviceId"] as? String, "device-123")
        XCTAssertEqual(json["expectedVersion"] as? String, "4")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(json["operationId"] as? String)))
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testRevocationFailureKeepsStoredDeviceIDForRetry() async {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        RevocationStubURLProtocol.handler = { request in
            let responseBody = #"{"code":"internal","message":"request failed"}"#
            let method = request.url?.lastPathComponent
            let status = method == "ListDevices" ? 200 : method == "RevokeDevice" ? 500 : 200
            let body = status == 200
                ? (method == "ListDevices" ? #"{"devices":[{"id":"device-123","status":"ACTIVE","version":"4"}]}"# : #"{"deleted":true}"#)
                : responseBody
            return (Self.response(for: request, status: status), Data(body.utf8))
        }

        do {
            try await repository().revokeRegisteredDevice(client: client())
            XCTFail("Expected the backend failure to be surfaced")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/RevokeDevice"))
            XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-123")
        }
    }

    func testRetriesCommittedRevocationWithSameOperationIDWhenEndpointCleanupFails() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methods: [String] = []
        var operationIDs: [String] = []
        var failEndpointCleanupOnce = true
        RevocationStubURLProtocol.handler = { request in
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
        XCTAssertNotNil(defaults.string(forKey: "mobile.device.revoke.pendingOperationID"))

        try await repository().revokeRegisteredDevice(client: client())

        XCTAssertEqual(methods, ["ListDevices", "RevokeDevice", "DeleteNotificationEndpoint", "RevokeDevice", "DeleteNotificationEndpoint"])
        XCTAssertEqual(operationIDs.count, 2)
        XCTAssertEqual(operationIDs[0], operationIDs[1])
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.registrationID"))
        XCTAssertNil(defaults.string(forKey: "mobile.device.revoke.pendingOperationID"))
    }

    func testCleansNotificationEndpointWhenServerAlreadyRevokedTheDevice() async throws {
        defaults.set("device-123", forKey: "mobile.device.id")
        defaults.set("registration-123", forKey: "mobile.device.registrationID")
        var methods: [String] = []
        RevocationStubURLProtocol.handler = { request in
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

    private func repository() -> ConfiguredDeviceRevocationRepository {
        ConfiguredDeviceRevocationRepository(defaults: defaults)
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RevocationStubURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: RevocationStaticTokenProvider()
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

private struct RevocationStaticTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "test-access-token" }
}

private final class RevocationStubURLProtocol: URLProtocol {
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
