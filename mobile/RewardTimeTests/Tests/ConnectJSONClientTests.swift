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

    private func makeClient(token: String?) -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: StaticTokenProvider(token: token)
        )
    }
}

private struct EmptyRequest: Encodable {}
private struct GroupsResponse: Decodable { let groups: [String] }

private struct StaticTokenProvider: AccessTokenProviding {
    let token: String?
    func accessToken() async throws -> String? { token }
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
