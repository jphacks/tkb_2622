import Foundation
import XCTest
@testable import ConnectJSONClient

final class ConnectJSONClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testCallSendsConnectRequestWithBearerTokenAndDecodesResponse() async throws {
        let body = Data(#"{"groups":[]}"#.utf8)
        var receivedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            receivedRequest = request
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        let client = makeClient(token: "test-access-token")

        let response: GroupsResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "ListGroups",
            requestBody: EmptyRequest(),
            responseType: GroupsResponse.self
        )

        XCTAssertEqual(response.groups, [])
        XCTAssertEqual(receivedRequest?.url?.path, "/group.v1.GroupService/ListGroups")
        XCTAssertEqual(receivedRequest?.httpMethod, "POST")
        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testCallPreservesConnectErrorCodeForRetryAndErrorUI() async throws {
        StubURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":"internal","message":"request failed"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected the Connect error to be surfaced")
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "internal")
        }
    }

    func testCallPreservesPlainHTTPStatusWhenResponseIsNotConnectJSON() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"message":"route missing"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected HTTP status to be preserved")
        } catch ConnectJSONClient.ClientError.httpStatus(let status) {
            XCTAssertEqual(status, 404)
        }
    }

    func testCallPreservesUnauthenticatedCodeAndProjectGuidanceFor401() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"unauthenticated","message":"authentication required"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected unauthenticated Connect error")
        } catch let error as ConnectJSONClient.ClientError {
            guard case .connect(let code) = error else { return XCTFail("Expected Connect error, got \(error)") }
            XCTAssertEqual(code, "unauthenticated")
            XCTAssertTrue(error.localizedDescription.contains("Project URL"))
        }
    }

    func testCallPreservesPermissionDeniedConnectCodeFor403() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"permission_denied","message":"forbidden"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected permission denied Connect error")
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "permission_denied")
        }
    }

    func testGetPreservesConnectErrorCodeForRESTEndpoint() async throws {
        var receivedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            receivedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"not_found","message":"feed missing"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.get(
                path: "v1/group/work-starts",
                queryItems: [],
                responseType: GroupsResponse.self
            )
            XCTFail("Expected REST Connect error to be surfaced")
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "not_found")
        }

        XCTAssertEqual(receivedRequest?.url?.path, "/v1/group/work-starts")
        XCTAssertEqual(receivedRequest?.httpMethod, "GET")
        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
    }

    func testCallPropagatesNetworkFailureWithoutConvertingItToHTTPError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }

    func testCallPropagatesTimeoutWithoutConvertingItToHTTPError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
    }

    func testCallSurfacesDecodeFailureForSuccessfulButMalformedJSON() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"groups":"not-an-array"}"#.utf8))
        }
        let client = makeClient(token: "test-access-token")

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected successful HTTP response with invalid DTO to fail decoding")
        } catch is DecodingError {}
    }

    func testCallDoesNotSendRequestWithoutAccessToken() async throws {
        StubURLProtocol.handler = { _ in
            XCTFail("A request must not be sent without an access token")
            throw URLError(.userAuthenticationRequired)
        }
        let client = makeClient(token: nil)

        do {
            let _: GroupsResponse = try await client.call(
                service: "group.v1.GroupService",
                method: "ListGroups",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected missing access token")
        } catch ConnectJSONClient.ClientError.missingAccessToken {}
    }

    func testCallLabelsTokenRefreshFailureAsPreflightFailureAndDoesNotSendAPIRequest() async throws {
        StubURLProtocol.handler = { _ in
            XCTFail("The API request must not be sent when token refresh fails")
            throw URLError(.cancelled)
        }
        let client = ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: makeSession(),
            tokenProvider: FailingTokenProvider(error: URLError(.timedOut))
        )

        do {
            let _: GroupsResponse = try await client.call(
                service: "identity.v1.IdentityService",
                method: "EnsureUser",
                requestBody: EmptyRequest(),
                responseType: GroupsResponse.self
            )
            XCTFail("Expected token refresh failure")
        } catch let error as ConnectJSONClient.ClientError {
            guard case .tokenProviderFailed(let underlying) = error else {
                return XCTFail("Expected token preflight error, got \(error)")
            }
            XCTAssertEqual((underlying as? URLError)?.code, .timedOut)
            XCTAssertTrue(error.localizedDescription.contains("アクセストークン"))
        }
    }

    private func makeClient(token: String?) -> ConnectJSONClient {
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: makeSession(),
            tokenProvider: StaticTokenProvider(token: token)
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct EmptyRequest: Encodable {}
private struct GroupsResponse: Decodable { let groups: [String] }

private struct StaticTokenProvider: AccessTokenProviding {
    let token: String?
    func accessToken() async throws -> String? { token }
}

private struct FailingTokenProvider: AccessTokenProviding {
    let error: Error
    func accessToken() async throws -> String? { throw error }
}

private final class StubURLProtocol: URLProtocol {
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
