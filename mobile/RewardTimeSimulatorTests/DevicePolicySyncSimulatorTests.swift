import Foundation
import XCTest
@testable import RewardTime

final class DevicePolicySyncSimulatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DevicePolicySyncSimulatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        DevicePolicySyncURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCreatesPolicyWhenNoPolicyExists() async throws {
        let methods = LockedRequestMethods()
        DevicePolicySyncURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "RegisterDevice":
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            case "GetRestrictionPolicy":
                return (404, #"{"code":"not_found","message":"policy missing"}"#)
            case "UpdateRestrictionPolicy":
                return (200, #"{"policy":{"deviceId":"device-1","status":"POLICY_STATUS_ENABLED","targetMode":"TARGET_MODE_SELECTED_APPS","deviceConfigVersion":"4","configured":true,"version":"1"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let policy = try await repository().sync(
            settings: DeviceRestrictionSettings(
                enabled: true,
                targetMode: "TARGET_MODE_SELECTED_APPS",
                configured: true,
                deviceConfigVersion: 4
            ),
            client: client(),
            deviceName: "Simulator"
        )

        XCTAssertEqual(methods.values, ["RegisterDevice", "GetRestrictionPolicy", "UpdateRestrictionPolicy"])
        XCTAssertEqual(policy.deviceID, "device-1")
        XCTAssertEqual(policy.policyVersion, 1)
    }

    func testResyncsMatchingPolicyWhenServerNeedsCurrentDevicePermissionReport() async throws {
        let methods = LockedRequestMethods()
        DevicePolicySyncURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "RegisterDevice":
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            case "GetRestrictionPolicy":
                return (200, #"{"policy":{"deviceId":"device-1","status":"POLICY_STATUS_PERMISSION_REQUIRED","targetMode":"TARGET_MODE_SELECTED_APPS","deviceConfigVersion":"4","configured":true,"version":"2"}}"#)
            case "UpdateRestrictionPolicy":
                return (200, #"{"policy":{"deviceId":"device-1","status":"POLICY_STATUS_PERMISSION_REQUIRED","targetMode":"TARGET_MODE_SELECTED_APPS","deviceConfigVersion":"4","configured":true,"version":"3"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let policy = try await repository().sync(
            settings: DeviceRestrictionSettings(
                enabled: true,
                targetMode: "TARGET_MODE_SELECTED_APPS",
                configured: true,
                deviceConfigVersion: 4
            ),
            client: client(),
            deviceName: "Simulator"
        )

        XCTAssertEqual(methods.values, ["RegisterDevice", "GetRestrictionPolicy", "UpdateRestrictionPolicy"])
        XCTAssertEqual(policy.policyVersion, 3)
    }

    func testReloadsPolicyAfterVersionConflictAndAcceptsMatchingServerState() async throws {
        let methods = LockedRequestMethods()
        var policyReadCount = 0
        DevicePolicySyncURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "RegisterDevice":
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            case "GetRestrictionPolicy":
                policyReadCount += 1
                let version = policyReadCount == 1 ? "2" : "3"
                let mode = policyReadCount == 1 ? "TARGET_MODE_ALL_NON_SYSTEM" : "TARGET_MODE_SELECTED_APPS"
                return (200, #"{"policy":{"deviceId":"device-1","status":"POLICY_STATUS_ENABLED","targetMode":"\#(mode)","deviceConfigVersion":"4","configured":true,"version":"\#(version)"}}"#)
            case "UpdateRestrictionPolicy":
                return (409, #"{"code":"aborted","message":"version changed"}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let policy = try await repository().sync(
            settings: DeviceRestrictionSettings(
                enabled: true,
                targetMode: "TARGET_MODE_SELECTED_APPS",
                configured: true,
                deviceConfigVersion: 4
            ),
            client: client(),
            deviceName: "Simulator"
        )

        XCTAssertEqual(methods.values, [
            "RegisterDevice", "GetRestrictionPolicy", "UpdateRestrictionPolicy", "GetRestrictionPolicy",
        ])
        XCTAssertEqual(policy.policyVersion, 3)
    }

    func testIncludesFailingGetPolicyOperationWhenPolicySyncFails() async {
        let methods = LockedRequestMethods()
        DevicePolicySyncURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            if method == "RegisterDevice" {
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            }
            return (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            _ = try await repository().sync(
                settings: DeviceRestrictionSettings(
                    enabled: true,
                    targetMode: "TARGET_MODE_SELECTED_APPS",
                    configured: true,
                    deviceConfigVersion: 4
                ),
                client: client(),
                deviceName: "Simulator"
            )
            XCTFail("Expected the policy read request to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/GetRestrictionPolicy"))
        }

        XCTAssertEqual(methods.values, ["RegisterDevice", "GetRestrictionPolicy"])
    }

    func testIncludesFailingUpdatePolicyOperationWithoutRetryingAsVersionConflict() async {
        let methods = LockedRequestMethods()
        DevicePolicySyncURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "RegisterDevice":
                return (200, #"{"device":{"id":"device-1","status":"ACTIVE"}}"#)
            case "GetRestrictionPolicy":
                return (404, #"{"code":"not_found","message":"policy missing"}"#)
            case "UpdateRestrictionPolicy":
                return (500, #"{"code":"internal","message":"request failed"}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        do {
            _ = try await repository().sync(
                settings: DeviceRestrictionSettings(
                    enabled: true,
                    targetMode: "TARGET_MODE_SELECTED_APPS",
                    configured: true,
                    deviceConfigVersion: 4
                ),
                client: client(),
                deviceName: "Simulator"
            )
            XCTFail("Expected the policy update request to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/UpdateRestrictionPolicy"))
        }

        XCTAssertEqual(methods.values, ["RegisterDevice", "GetRestrictionPolicy", "UpdateRestrictionPolicy"])
    }

    private func repository() -> ConfiguredDeviceSettingsRepository {
        ConfiguredDeviceSettingsRepository(defaults: defaults)
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DevicePolicySyncURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: DevicePolicySyncTokenProvider()
        )
    }

}

private struct DevicePolicySyncTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedRequestMethods {
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

private final class DevicePolicySyncURLProtocol: URLProtocol {
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
