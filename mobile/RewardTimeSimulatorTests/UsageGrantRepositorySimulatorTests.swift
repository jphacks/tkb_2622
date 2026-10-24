import Foundation
import XCTest
@testable import RewardTime

final class UsageGrantRepositorySimulatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UsageGrantRepositorySimulatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        UsageGrantRepositoryURLProtocol.handler = nil
    }

    override func tearDown() {
        UsageGrantRepositoryURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReserveUsesBackendContractAndDecodesGrantAndRestrictionState() async throws {
        defaults.set("device-1", forKey: "mobile.device.id")
        let requests = LockedUsageGrantRequests()
        UsageGrantRepositoryURLProtocol.handler = { request in
            requests.append(request)
            return (200, #"{"grant":{"id":"grant-1","reservedSeconds":"300","reportedSeconds":"0","status":"GRANT_STATUS_ACTIVE","controlRevision":"9"},"state":{"deviceId":"device-1","controlRevision":"9","desiredMode":"DESIRED_MODE_TIMED_UNLOCK"}}"#)
        }

        let result = try await repository().reserve(
            operationID: "operation-1",
            sessionID: "session-1",
            expectedSessionVersion: 12,
            requestedSeconds: 300
        )

        let captured = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(requests.values.count, 1)
        XCTAssertEqual(captured.url?.path, "/restriction.v1.RestrictionService/ReserveUsageGrant")
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer simulator-test-token")
        let body = try XCTUnwrap(requestBody(from: captured))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload["operationId"], "operation-1")
        XCTAssertEqual(payload["sessionId"], "session-1")
        XCTAssertEqual(payload["expectedSessionVersion"], "12")
        XCTAssertEqual(payload["deviceId"], "device-1")
        XCTAssertEqual(payload["requestedSeconds"], "300")
        XCTAssertEqual(result.grant.id, "grant-1")
        XCTAssertEqual(result.grant.reservedSeconds, 300)
        XCTAssertEqual(result.grant.reportedSeconds, 0)
        XCTAssertEqual(result.deviceID, "device-1")
        XCTAssertEqual(result.controlRevision, 9)
        XCTAssertEqual(result.desiredMode, "DESIRED_MODE_TIMED_UNLOCK")
    }

    func testReservePreservesBackendConnectErrorCode() async throws {
        defaults.set("device-1", forKey: "mobile.device.id")
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (404, #"{"code":"not_found","message":"session missing"}"#)
        }

        do {
            _ = try await repository().reserve(
                operationID: "operation-1",
                sessionID: "missing-session",
                expectedSessionVersion: 12,
                requestedSeconds: 300
            )
            XCTFail("Expected the backend Connect error to be surfaced")
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "not_found")
        }
    }

    private func repository() -> ConfiguredUsageGrantRepository {
        ConfiguredUsageGrantRepository(client: client(), defaults: defaults)
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageGrantRepositoryURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: UsageGrantRepositoryTokenProvider()
        )
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        var body = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            if count <= 0 { break }
            body.append(buffer, count: count)
        }
        return body.isEmpty ? nil : body
    }
}

private struct UsageGrantRepositoryTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedUsageGrantRequests {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }

    var values: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class UsageGrantRepositoryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
