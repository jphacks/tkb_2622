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
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(not_found)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/ReserveUsageGrant"))
        }
    }

    func testGetGrantAndReportUsageUseBackendRoutesAndProtoJSONValues() async throws {
        let requests = LockedUsageGrantRequests()
        UsageGrantRepositoryURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "GetUsageGrant":
                return (200, #"{"grant":{"id":"grant-1","reservedSeconds":"300","reportedSeconds":"60","status":"GRANT_STATUS_ACTIVE","controlRevision":"9","consumedSeconds":"60"}}"#)
            case "ReportUsage":
                return (200, #"{"grant":{"id":"grant-1","reservedSeconds":"300","reportedSeconds":"120","status":"GRANT_STATUS_ACTIVE","controlRevision":"10"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }
        let repository = repository()

        let current = try await repository.getGrant(grantID: "grant-1")
        let reported = try await repository.reportUsage(
            operationID: "report-operation-1",
            grantID: "grant-1",
            reportSequence: 2,
            cumulativeSeconds: 120,
            observedAt: ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z")!,
            final: false
        )

        let captured = requests.values
        XCTAssertEqual(captured.map { $0.url?.lastPathComponent }, ["GetUsageGrant", "ReportUsage"])
        XCTAssertEqual(captured.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer simulator-test-token", "Bearer simulator-test-token",
        ])
        let getPayload = try requestPayload(from: captured[0])
        XCTAssertEqual(getPayload["grantId"] as? String, "grant-1")
        let reportPayload = try requestPayload(from: captured[1])
        XCTAssertEqual(reportPayload["operationId"] as? String, "report-operation-1")
        XCTAssertEqual(reportPayload["grantId"] as? String, "grant-1")
        XCTAssertEqual(reportPayload["reportSeq"] as? String, "2")
        XCTAssertEqual(reportPayload["cumulativeSeconds"] as? String, "120")
        XCTAssertEqual(reportPayload["observedAt"] as? String, "2026-10-25T10:00:00.000Z")
        XCTAssertEqual(reportPayload["final"] as? Bool, false)
        XCTAssertEqual(current.reportedSeconds, 60)
        XCTAssertTrue(current.isSettled)
        XCTAssertEqual(reported.reportedSeconds, 120)
        XCTAssertEqual(reported.controlRevision, 10)
    }

    func testReservationOperationDistinguishesSucceededAndNotFound() async throws {
        let requests = LockedUsageGrantRequests()
        var operationCount = 0
        UsageGrantRepositoryURLProtocol.handler = { request in
            requests.append(request)
            operationCount += 1
            if operationCount == 1 {
                return (200, #"{"status":"OPERATION_STATUS_SUCCEEDED","resourceId":"grant-1"}"#)
            }
            return (200, #"{"status":"OPERATION_STATUS_NOT_FOUND","resourceId":""}"#)
        }
        let repository = repository()

        let succeeded = try await repository.reservationOperation(operationID: "reserve-operation-1")
        let pending = try await repository.reservationOperation(operationID: "reserve-operation-2")

        XCTAssertEqual(succeeded, "grant-1")
        XCTAssertNil(pending)
        XCTAssertEqual(requests.values.map { $0.url?.lastPathComponent }, [
            "GetRestrictionOperation", "GetRestrictionOperation",
        ])
        for (request, expectedOperationID) in zip(requests.values, ["reserve-operation-1", "reserve-operation-2"]) {
            let payload = try requestPayload(from: request)
            XCTAssertEqual(payload["kind"] as? String, "OPERATION_KIND_RESERVE")
            XCTAssertEqual(payload["operationId"] as? String, expectedOperationID)
        }
    }

    func testReportRestrictionStateFailureIncludesFailingOperation() async {
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            try await repository().reportRestrictionState(
                deviceID: "device-1",
                controlRevision: 9,
                shieldStatus: "SHIELD_STATUS_UNSHIELDED",
                permissionStatus: "PERMISSION_STATUS_GRANTED"
            )
            XCTFail("Expected ReportRestrictionState error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/ReportRestrictionState"))
        }
    }

    func testStoredActiveGrantSyncPropagatesFailureForHomeStatus() async {
        let sharedSuite = "UsageGrantSyncFailure.\(UUID().uuidString)"
        let shared = UserDefaults(suiteName: sharedSuite)!
        defer { shared.removePersistentDomain(forName: sharedSuite) }
        shared.set("grant-1", forKey: "mobile.usage.activeGrantID")
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            try await repository().synchronizeStoredActiveGrantIfPresent(shared: shared)
            XCTFail("Expected stored grant sync error to reach the caller")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/GetUsageGrant"))
        }
    }

    func testGetGrantFailureIncludesFailingOperation() async {
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (404, #"{"code":"not_found","message":"grant missing"}"#)
        }

        do {
            _ = try await repository().getGrant(grantID: "grant-1")
            XCTFail("Expected GetUsageGrant error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(not_found)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/GetUsageGrant"))
        }
    }

    func testReportUsageFailureIncludesFailingOperation() async {
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            _ = try await repository().reportUsage(
                operationID: "report-operation-1",
                grantID: "grant-1",
                reportSequence: 2,
                cumulativeSeconds: 120,
                observedAt: Date(timeIntervalSince1970: 1_791_000_000),
                final: false
            )
            XCTFail("Expected ReportUsage error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/ReportUsage"))
        }
    }

    func testReservationOperationFailureIncludesFailingOperation() async {
        UsageGrantRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            _ = try await repository().reservationOperation(operationID: "reserve-operation-1")
            XCTFail("Expected GetRestrictionOperation error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("restriction.v1.RestrictionService/GetRestrictionOperation"))
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

    private func requestPayload(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(requestBody(from: request))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
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
