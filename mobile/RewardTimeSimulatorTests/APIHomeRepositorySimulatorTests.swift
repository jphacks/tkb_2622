import Foundation
import XCTest
@testable import RewardTime

final class APIHomeRepositorySimulatorTests: XCTestCase {
    override func tearDown() {
        APIHomeURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchesConsistentHomeSnapshotFromAllThreeAPIs() async throws {
        let methods = LockedMethods()
        APIHomeURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.insert(method)
            switch method {
            case "GetCurrentSession":
                return (200, #"{"session":{"id":"session-1","status":"SESSION_STATUS_RUNNING","version":"3","minimumReached":true,"taskSnapshot":{"minimumSeconds":"3600"},"durations":{"activeMillis":"120000"}}}"#)
            case "GetBalance":
                return (200, #"{"balance":{"sessionId":"session-1","balanceSeconds":"7200"}}"#)
            case "GetRestrictionState":
                return (200, #"{"state":{"sessionId":"session-1","deviceId":"device-1","controlRevision":"4","desiredMode":"DESIRED_MODE_SHIELDED","appliedRevision":"4","shieldStatus":"SHIELD_STATUS_SHIELDED","permissionStatus":"PERMISSION_STATUS_GRANTED"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let snapshot = try await repository().fetchCurrentSnapshot()

        XCTAssertEqual(methods.values, ["GetCurrentSession", "GetBalance", "GetRestrictionState"])
        XCTAssertEqual(snapshot.sessionStatus, .working)
        XCTAssertEqual(snapshot.sessionID, "session-1")
        XCTAssertEqual(snapshot.sessionVersion, 3)
        XCTAssertEqual(snapshot.elapsedMinutes, 2)
        XCTAssertEqual(snapshot.rewardBalanceMinutes, 120)
        XCTAssertEqual(snapshot.desiredRestriction, .shielded)
        XCTAssertEqual(snapshot.restrictionDeviceID, "device-1")
        XCTAssertEqual(snapshot.restrictionControlRevision, 4)
        XCTAssertFalse(snapshot.isSampleData)
    }

    func testRetriesOnceWhenSessionChangesBetweenParallelHomeReads() async throws {
        let attempts = LockedRequestCounts()
        APIHomeURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            let attempt = attempts.increment(method)
            switch method {
            case "GetCurrentSession":
                let id = attempt == 1 ? "session-old" : "session-new"
                return (200, #"{"session":{"id":"\#(id)","status":"SESSION_STATUS_RUNNING","version":"2","durations":{"activeMillis":"60000"}}}"#)
            case "GetBalance":
                let id = attempt == 1 ? "session-new" : "session-new"
                return (200, #"{"balance":{"sessionId":"\#(id)","balanceSeconds":"300"}}"#)
            case "GetRestrictionState":
                let id = attempt == 1 ? "session-old" : "session-new"
                return (200, #"{"state":{"sessionId":"\#(id)","deviceId":"device-1","controlRevision":"1","desiredMode":"DESIRED_MODE_UNRESTRICTED","appliedRevision":"1","shieldStatus":"SHIELD_STATUS_UNSHIELDED","permissionStatus":"PERMISSION_STATUS_GRANTED"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let snapshot = try await repository().fetchCurrentSnapshot()

        XCTAssertEqual(snapshot.sessionID, "session-new")
        XCTAssertEqual(attempts.value(for: "GetCurrentSession"), 2)
        XCTAssertEqual(attempts.value(for: "GetBalance"), 2)
        XCTAssertEqual(attempts.value(for: "GetRestrictionState"), 2)
    }

    func testEachFailedHomeAPIIncludesItsOperationAndNeverReturnsPartialSnapshot() async {
        let operations = [
            (method: "GetCurrentSession", path: "focus.v1.FocusService/GetCurrentSession"),
            (method: "GetBalance", path: "reward.v1.RewardService/GetBalance"),
            (method: "GetRestrictionState", path: "restriction.v1.RestrictionService/GetRestrictionState"),
        ]

        for failedOperation in operations {
            APIHomeURLProtocol.handler = { request in
                let method = request.url?.lastPathComponent ?? ""
                if method == failedOperation.method {
                    return (500, #"{"code":"internal","message":"request failed"}"#)
                }
                switch method {
                case "GetCurrentSession":
                    return (200, #"{"session":null}"#)
                case "GetBalance":
                    return (200, #"{"balance":{"sessionId":"","balanceSeconds":"0"}}"#)
                default:
                    return (200, #"{"state":{"sessionId":"","deviceId":"","controlRevision":"0","desiredMode":"DESIRED_MODE_UNRESTRICTED","appliedRevision":"0","shieldStatus":"SHIELD_STATUS_UNSHIELDED","permissionStatus":"PERMISSION_STATUS_GRANTED"}}"#)
                }
            }

            do {
                _ = try await repository().fetchCurrentSnapshot()
                XCTFail("A partial Home response must not be returned for \(failedOperation.method)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("(internal)"))
                XCTAssertTrue(error.localizedDescription.contains(failedOperation.path))
            }
        }
    }

    private func repository() -> APIHomeRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIHomeURLProtocol.self]
        return APIHomeRepository(
            baseURL: URL(string: "https://api.example.test")!,
            auth: APIHomeTokenProvider(),
            selectedApplicationCount: 2,
            session: URLSession(configuration: configuration)
        )
    }
}

private struct APIHomeTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedMethods {
    private let lock = NSLock()
    private var storage = Set<String>()

    func insert(_ method: String) {
        lock.lock()
        storage.insert(method)
        lock.unlock()
    }

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedRequestCounts {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func increment(_ method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        counts[method, default: 0] += 1
        return counts[method, default: 0]
    }

    func value(for method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[method, default: 0]
    }
}

private final class APIHomeURLProtocol: URLProtocol {
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
