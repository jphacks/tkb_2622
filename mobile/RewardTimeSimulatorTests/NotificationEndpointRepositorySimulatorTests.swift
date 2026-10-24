import Foundation
import XCTest
@testable import RewardTime

final class NotificationEndpointRepositorySimulatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NotificationEndpointRepositorySimulatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        NotificationEndpointRepositoryURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRegistersDeviceBeforeEndpointThroughRepository() async throws {
        let methods = LockedEndpointMethods()
        NotificationEndpointRepositoryURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "RegisterDevice":
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            case "RegisterNotificationEndpoint":
                return (200, #"{"registered":true}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        try await repository().register(
            token: String(repeating: "a", count: 64),
            environment: "development",
            client: client()
        )

        XCTAssertEqual(methods.values, ["RegisterDevice", "RegisterNotificationEndpoint"])
        XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-1")
        XCTAssertNotNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testDoesNotRegisterEndpointWhenDeviceRegistrationFails() async {
        let methods = LockedEndpointMethods()
        NotificationEndpointRepositoryURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            return (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            try await repository().register(
                token: String(repeating: "a", count: 64),
                environment: "development",
                client: client()
            )
            XCTFail("Endpoint registration must not run after device registration fails")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/RegisterDevice"))
        }

        XCTAssertEqual(methods.values, ["RegisterDevice"])
        XCTAssertNil(defaults.string(forKey: "mobile.device.id"))
    }

    func testPreservesConnectErrorFromNotificationEndpointRegistration() async {
        let methods = LockedEndpointMethods()
        NotificationEndpointRepositoryURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            if method == "RegisterDevice" {
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            }
            return (404, #"{"code":"not_found","message":"device endpoint missing"}"#)
        }

        do {
            try await repository().register(
                token: String(repeating: "a", count: 64),
                environment: "development",
                client: client()
            )
            XCTFail("The endpoint registration Connect error must be returned")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(not_found)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/RegisterNotificationEndpoint"))
        }

        XCTAssertEqual(methods.values, ["RegisterDevice", "RegisterNotificationEndpoint"])
    }

    func testPreservesDeleteNotificationEndpointOperationAndConnectError() async {
        let methods = LockedEndpointMethods()
        NotificationEndpointRepositoryURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            return (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            try await repository().delete(client: client())
            XCTFail("The notification endpoint deletion Connect error must be returned")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/DeleteNotificationEndpoint"))
        }

        XCTAssertEqual(methods.values, ["DeleteNotificationEndpoint"])
    }

    private func repository() -> ConfiguredNotificationEndpointRepository {
        ConfiguredNotificationEndpointRepository(defaults: defaults)
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotificationEndpointRepositoryURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: NotificationEndpointTokenProvider()
        )
    }
}

private struct NotificationEndpointTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedEndpointMethods {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ method: String) {
        lock.lock()
        storage.append(method)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class NotificationEndpointRepositoryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (statusCode, body) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
