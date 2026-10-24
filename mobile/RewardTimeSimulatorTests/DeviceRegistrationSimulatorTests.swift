import Foundation
import XCTest
@testable import RewardTime

final class DeviceRegistrationSimulatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DeviceRegistrationSimulatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        DeviceRegistrationURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRegisterDeviceUsesConnectRequestAndSavesReturnedDeviceID() async throws {
        var capturedRequest: URLRequest?
        DeviceRegistrationURLProtocol.handler = { request in
            capturedRequest = request
            return (200, #"{"device":{"id":"device-123","status":"ACTIVE"}}"#)
        }

        let repository = ConfiguredDeviceSettingsRepository(defaults: defaults)
        let deviceID = try await repository.ensureDeviceRegistered(client: client())

        XCTAssertEqual(deviceID, "device-123")
        XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-123")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(
            capturedRequest?.url?.path,
            "/identity.v1.IdentityService/RegisterDevice"
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer simulator-test-token")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(defaults.string(forKey: "mobile.device.registrationID"))
    }

    func testRegisterDeviceReusesOperationIDAfterInternalFailure() async throws {
        var requestCount = 0
        var responses = [
            (500, #"{"code":"internal","message":"request failed"}"#),
            (500, #"{"code":"internal","message":"request failed"}"#),
            (200, #"{"device":{"id":"device-123","status":"ACTIVE"}}"#),
        ]
        DeviceRegistrationURLProtocol.handler = { request in
            requestCount += 1
            return responses.removeFirst()
        }

        let repository = ConfiguredDeviceSettingsRepository(defaults: defaults)
        let registrationID = repository.stableRegistrationID()
        let operationKey = "mobile.device.register.operation.\(registrationID)"
        var failedOperationID: String?
        for _ in 0..<2 {
            do {
                _ = try await repository.ensureDeviceRegistered(client: client())
                XCTFail("Expected the device registration request to fail")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("(internal)"))
                XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/RegisterDevice"))
            }
            let currentOperationID = try XCTUnwrap(defaults.string(forKey: operationKey))
            if let previousOperationID = failedOperationID {
                XCTAssertEqual(currentOperationID, previousOperationID)
            }
            failedOperationID = currentOperationID
        }

        XCTAssertEqual(defaults.string(forKey: "mobile.device.registrationID"), registrationID)
        XCTAssertNotNil(failedOperationID)

        let deviceID = try await repository.ensureDeviceRegistered(client: client())

        XCTAssertEqual(deviceID, "device-123")
        XCTAssertEqual(requestCount, 3)
        XCTAssertNil(defaults.string(forKey: operationKey))
        XCTAssertEqual(defaults.string(forKey: "mobile.device.id"), "device-123")
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceRegistrationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: session,
            tokenProvider: DeviceRegistrationTokenProvider()
        )
    }
}

private struct DeviceRegistrationTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class DeviceRegistrationURLProtocol: URLProtocol {
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
