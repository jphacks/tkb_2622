import Foundation
import XCTest
@testable import RewardTime

final class IdentityRepositorySimulatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        IdentityRepositoryURLProtocol.handler = nil
    }

    override func tearDown() {
        IdentityRepositoryURLProtocol.handler = nil
        super.tearDown()
    }

    func testEnsureUserThenGetMeUsesBackendRoutesAndReturnsCurrentIdentity() async throws {
        let requests = LockedIdentityRequests()
        IdentityRepositoryURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "EnsureUser":
                return (200, #"{"user":{"id":"user-1","status":"ACTIVE","createdAt":"2026-10-25T09:00:00Z","displayName":"Chiho","avatarId":"fox"}}"#)
            case "GetMe":
                return (200, #"{"user":{"id":"user-1","status":"ACTIVE","createdAt":"2026-10-25T09:00:00Z","displayName":"Chiho","avatarId":"fox"}}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }

        let identity = try await repository().ensureUserAndFetchCurrentUser(operationID: "ensure-operation-1")

        let captured = requests.values
        XCTAssertEqual(captured.map { $0.url?.path }, [
            "/identity.v1.IdentityService/EnsureUser",
            "/identity.v1.IdentityService/GetMe",
        ])
        XCTAssertEqual(captured.map { $0.httpMethod }, ["POST", "POST"])
        XCTAssertEqual(captured.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer simulator-test-token", "Bearer simulator-test-token",
        ])
        XCTAssertEqual(try payload(from: captured[0])["operationId"] as? String, "ensure-operation-1")
        XCTAssertEqual(identity.id, "user-1")
        XCTAssertEqual(identity.displayName, "Chiho")
        XCTAssertEqual(identity.avatarID, "fox")
    }

    func testEnsureUserFailurePreservesConnectCodeAndSkipsGetMe() async throws {
        let requests = LockedIdentityRequests()
        IdentityRepositoryURLProtocol.handler = { request in
            requests.append(request)
            return (500, #"{"code":"internal","message":"ensure failed"}"#)
        }

        do {
            _ = try await repository().ensureUserAndFetchCurrentUser(operationID: "ensure-operation-1")
            XCTFail("Expected EnsureUser error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/EnsureUser"))
        }

        XCTAssertEqual(requests.values.map { $0.url?.lastPathComponent }, ["EnsureUser"])
    }

    func testUpdateAvatarUsesBackendAvatarIdFieldAndRoute() async throws {
        let requests = LockedIdentityRequests()
        IdentityRepositoryURLProtocol.handler = { request in
            requests.append(request)
            return (200, #"{"user":{"id":"user-1","status":"ACTIVE","createdAt":"2026-10-25T09:00:00Z","displayName":"Chiho","avatarId":"fox"}}"#)
        }

        let identity = try await repository().updateAvatar("fox")

        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.url?.path, "/identity.v1.IdentityService/UpdateAvatar")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer simulator-test-token")
        XCTAssertEqual(try payload(from: request)["avatarId"] as? String, "fox")
        XCTAssertEqual(identity.avatarID, "fox")
    }

    func testUpdateDisplayNameUsesBackendFieldAndRoute() async throws {
        let requests = LockedIdentityRequests()
        IdentityRepositoryURLProtocol.handler = { request in
            requests.append(request)
            return (200, #"{"user":{"id":"user-1","status":"ACTIVE","createdAt":"2026-10-25T09:00:00Z","displayName":"Chiho Focus","avatarId":"fox"}}"#)
        }

        let identity = try await repository().updateDisplayName("Chiho Focus")

        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.url?.path, "/identity.v1.IdentityService/UpdateDisplayName")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer simulator-test-token")
        XCTAssertEqual(try payload(from: request)["displayName"] as? String, "Chiho Focus")
        XCTAssertEqual(identity.displayName, "Chiho Focus")
    }

    func testGetMeFailureIncludesFailingIdentityOperation() async {
        let requests = LockedIdentityRequests()
        IdentityRepositoryURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.lastPathComponent == "EnsureUser" {
                return (200, #"{"user":{"id":"user-1","status":"ACTIVE","createdAt":"2026-10-25T09:00:00Z","displayName":"Chiho","avatarId":"fox"}}"#)
            }
            return (404, #"{"code":"not_found","message":"user missing"}"#)
        }

        do {
            _ = try await repository().ensureUserAndFetchCurrentUser(operationID: "ensure-operation-1")
            XCTFail("Expected GetMe error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(not_found)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/GetMe"))
        }

        XCTAssertEqual(requests.values.map { $0.url?.lastPathComponent }, ["EnsureUser", "GetMe"])
    }

    func testUpdateAvatarFailureIncludesFailingIdentityOperation() async {
        IdentityRepositoryURLProtocol.handler = { _ in
            (404, #"{"code":"not_found","message":"avatar update route missing"}"#)
        }

        do {
            _ = try await repository().updateAvatar("fox")
            XCTFail("Expected UpdateAvatar error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(not_found)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/UpdateAvatar"))
        }
    }

    func testUpdateDisplayNameFailureIncludesFailingIdentityOperation() async {
        IdentityRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"request failed"}"#)
        }

        do {
            _ = try await repository().updateDisplayName("Chiho Focus")
            XCTFail("Expected UpdateDisplayName error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("(internal)"))
            XCTAssertTrue(error.localizedDescription.contains("identity.v1.IdentityService/UpdateDisplayName"))
        }
    }

    private func repository() -> IdentityAPIRepository {
        IdentityAPIRepository(client: ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: sessionConfiguration()),
            tokenProvider: IdentityRepositoryTokenProvider()
        ))
    }

    private func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityRepositoryURLProtocol.self]
        return configuration
    }

    private func payload(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody ?? request.httpBodyStream.flatMap(read))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func read(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

private struct IdentityRepositoryTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedIdentityRequests {
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

private final class IdentityRepositoryURLProtocol: URLProtocol {
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
