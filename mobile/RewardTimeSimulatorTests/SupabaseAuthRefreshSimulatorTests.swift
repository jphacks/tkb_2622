import Foundation
import Supabase
import XCTest
@testable import RewardTime

final class SupabaseAuthRefreshSimulatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AuthRefreshURLProtocol.handler = nil
    }

    override func tearDown() {
        AuthRefreshURLProtocol.handler = nil
        super.tearDown()
    }

    func testEmailOTPRequestUsesSharedSignupCapableFlow() async throws {
        let requests = LockedAuthRequests()
        AuthRefreshURLProtocol.handler = { request in
            requests.append(request)
            return (200, "")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRefreshURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.example.test")!,
            supabaseKey: "simulator-publishable-key",
            options: SupabaseClientOptions(
                auth: .init(storage: LockedAuthLocalStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration))
            )
        )

        try await SupabaseAuthService(client: client).sendEmailOTP(to: "person@example.test")

        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/otp")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody ?? request.httpBodyStream.flatMap(read))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["email"] as? String, "person@example.test")
        XCTAssertEqual(payload["create_user"] as? Bool, true)
    }

    func testEmailOTPVerificationUsesEmailTypeAndStoresSession() async throws {
        let requests = LockedAuthRequests()
        AuthRefreshURLProtocol.handler = { request in
            requests.append(request)
            return (200, Self.refreshedSessionJSON)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRefreshURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.example.test")!,
            supabaseKey: "simulator-publishable-key",
            options: SupabaseClientOptions(
                auth: .init(storage: LockedAuthLocalStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
        let service = SupabaseAuthService(client: client)

        try await service.verifyEmailOTP(email: "person@example.test", code: "123456")
        let accessToken = try await service.accessToken()

        XCTAssertEqual(accessToken, "refreshed-simulator-access-token")
        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/verify")
        let body = try XCTUnwrap(request.httpBody ?? request.httpBodyStream.flatMap(read))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["email"] as? String, "person@example.test")
        XCTAssertEqual(payload["token"] as? String, "123456")
        XCTAssertEqual(payload["type"] as? String, "email")
    }

    func testExpiredStoredSessionRefreshesBeforeReturningAccessToken() async throws {
        let storage = LockedAuthLocalStorage()
        let storageKey = "simulator-expired-session"
        let oldSession = expiredSession()
        try storage.store(key: storageKey, value: JSONEncoder().encode(oldSession))
        let requests = LockedAuthRequests()
        AuthRefreshURLProtocol.handler = { request in
            requests.append(request)
            return (200, Self.refreshedSessionJSON)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRefreshURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://project.example.test")!,
            supabaseKey: "simulator-publishable-key",
            options: SupabaseClientOptions(
                auth: .init(
                    storage: storage,
                    storageKey: storageKey,
                    autoRefreshToken: false
                ),
                global: .init(session: URLSession(configuration: configuration))
            )
        )

        let accessToken = try await SupabaseAuthService(client: client).accessToken()

        XCTAssertEqual(accessToken, "refreshed-simulator-access-token")
        let captured = requests.values
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.url?.path, "/auth/v1/token")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(captured.first?.url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "grant_type", value: "refresh_token")])
        let body = try XCTUnwrap(captured.first?.httpBody ?? captured.first?.httpBodyStream.flatMap(read))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["refresh_token": "expired-simulator-refresh-token"])

        let persisted = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: storageKey)))
        XCTAssertEqual(persisted.accessToken, "refreshed-simulator-access-token")
        XCTAssertEqual(persisted.refreshToken, "rotated-simulator-refresh-token")
    }

    private func expiredSession() -> Session {
        let now = Date()
        let user = User(
            id: UUID(uuidString: "d3db82c0-7943-47f4-90c5-06455a5c1e1c")!,
            appMetadata: [:], userMetadata: [:], aud: "authenticated",
            email: "simulator@example.test", createdAt: now, updatedAt: now
        )
        return Session(
            accessToken: "expired-simulator-access-token",
            tokenType: "bearer",
            expiresIn: 0,
            expiresAt: now.timeIntervalSince1970 - 60,
            refreshToken: "expired-simulator-refresh-token",
            user: user
        )
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

    private static let refreshedSessionJSON = """
    {"access_token":"refreshed-simulator-access-token","token_type":"bearer","expires_in":3600,"expires_at":1898200000,"refresh_token":"rotated-simulator-refresh-token","user":{"id":"d3db82c0-7943-47f4-90c5-06455a5c1e1c","app_metadata":{},"user_metadata":{},"aud":"authenticated","email":"simulator@example.test","created_at":"2026-10-25T00:00:00Z","updated_at":"2026-10-25T00:00:00Z"}}
    """
}

private final class LockedAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        values[key] = nil
        lock.unlock()
    }
}

private final class LockedAuthRequests {
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

private final class AuthRefreshURLProtocol: URLProtocol {
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
