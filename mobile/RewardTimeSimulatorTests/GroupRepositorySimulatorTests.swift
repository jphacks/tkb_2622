import Foundation
import XCTest
@testable import RewardTime

final class GroupRepositorySimulatorTests: XCTestCase {
    override func tearDown() {
        GroupRepositoryURLProtocol.handler = nil
        super.tearDown()
    }

    func testGroupRPCsUseExpectedRoutesAndDecodeProtoJSONResponses() async throws {
        let methods = LockedGroupMethods()
        GroupRepositoryURLProtocol.handler = { request in
            let method = request.url?.lastPathComponent ?? ""
            methods.append(method)
            switch method {
            case "ListGroups":
                return (200, #"{"groups":[{"id":"group-1","name":"朝活","createdAt":"2026-10-25T09:00:00Z","members":[{"isCurrentUser":true,"displayName":"チホ","avatarId":"fox","joinedAt":"2026-10-25T09:01:00.123Z"}]}]}"#)
            case "CreateGroup", "AcceptInvitation":
                return (200, #"{"group":{"id":"group-1","name":"朝活","createdAt":"2026-10-25T09:00:00Z","members":[{"isCurrentUser":true,"displayName":"チホ","avatarId":"fox","joinedAt":"2026-10-25T09:01:00Z"}]}}"#)
            case "CreateInvitation":
                return (200, #"{"invitationId":"invitation-1","token":"invite-token","expiresAt":"2026-11-01T09:00:00Z"}"#)
            case "LeaveGroup":
                return (200, #"{"groupDeleted":true}"#)
            default:
                return (404, #"{"code":"not_found","message":"unknown route"}"#)
            }
        }
        let repository = repository()

        let groups = try await repository.fetchGroups()
        let createdGroup = try await repository.createGroup(name: "朝活", operationID: "operation-create")
        let invitation = try await repository.createInvitation(groupID: "group-1", operationID: "operation-invite")
        let acceptedGroup = try await repository.acceptInvitation(token: "invite-token", operationID: "operation-accept")
        let groupDeleted = try await repository.leaveGroup(groupID: "group-1", operationID: "operation-leave")

        XCTAssertEqual(methods.values, ["ListGroups", "CreateGroup", "CreateInvitation", "AcceptInvitation", "LeaveGroup"])
        XCTAssertEqual(groups.first?.id, "group-1")
        XCTAssertEqual(groups.first?.members.first?.displayName, "チホ")
        XCTAssertEqual(groups.first?.members.first?.avatarID, "fox")
        XCTAssertEqual(groups.first?.members.first?.isCurrentUser, true)
        XCTAssertEqual(createdGroup.name, "朝活")
        XCTAssertEqual(acceptedGroup.id, "group-1")
        XCTAssertEqual(invitation.id, "invitation-1")
        XCTAssertEqual(invitation.token, "invite-token")
        XCTAssertEqual(invitation.expiresAt.date, ISO8601DateFormatter().date(from: "2026-11-01T09:00:00Z"))
        XCTAssertTrue(groupDeleted)
    }

    func testListGroupsPreservesConnectErrorCode() async {
        GroupRepositoryURLProtocol.handler = { _ in
            (500, #"{"code":"internal","message":"group query failed"}"#)
        }

        do {
            _ = try await repository().fetchGroups()
            XCTFail("The Group RPC error must be returned")
        } catch ConnectJSONClient.ClientError.connect(let code) {
            XCTAssertEqual(code, "internal")
        } catch {
            XCTFail("Expected the Connect error, got \(error)")
        }
    }

    func testWorkStartFeedUsesBackendCursorAndPersistsTheNextPagePosition() async throws {
        let suiteName = "GroupWorkStartsSimulatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let requests = LockedGroupRequests()
        var responseCount = 0
        GroupRepositoryURLProtocol.handler = { request in
            requests.append(request)
            responseCount += 1
            if responseCount == 1 {
                return (200, #"{"events":[{"event_id":"event-1","started_at":"2026-10-25T09:01:00.123Z"}],"next_started_at":"2026-10-25T09:01:00.123Z","next_event_id":"event-1"}"#)
            }
            return (200, #"{"events":[]}"#)
        }
        let repository = APIGroupRepository(
            baseURL: URL(string: "https://api.example.test")!,
            client: client(),
            authenticatedUserID: { "user-1" },
            defaults: defaults
        )

        let firstPage = try await repository.fetchWorkStarts()
        let secondPage = try await repository.fetchWorkStarts()

        let captured = requests.values
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(firstPage.map { $0.eventID }, ["event-1"])
        XCTAssertEqual(firstPage.first?.startedAt.date, timestampFormatter.date(from: "2026-10-25T09:01:00.123Z"))
        XCTAssertTrue(secondPage.isEmpty)
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].url?.path, "/v1/group/work-starts")
        XCTAssertEqual(captured[0].httpMethod, "GET")
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "Authorization"), "Bearer simulator-test-token")
        XCTAssertEqual(queryValue("page_size", in: captured[0]), "50")
        XCTAssertEqual(queryValue("after_event_id", in: captured[0]), nil)
        XCTAssertEqual(queryValue("after_started_at", in: captured[1]), "2026-10-25T09:01:00.123Z")
        XCTAssertEqual(queryValue("after_event_id", in: captured[1]), "event-1")
    }

    private func repository() -> APIGroupRepository {
        APIGroupRepository(
            baseURL: URL(string: "https://api.example.test")!,
            client: client()
        )
    }

    private func client() -> ConnectJSONClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GroupRepositoryURLProtocol.self]
        return ConnectJSONClient(
            baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: GroupRepositoryTokenProvider()
        )
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}

private struct GroupRepositoryTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { "simulator-test-token" }
}

private final class LockedGroupMethods {
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

private final class LockedGroupRequests {
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

private final class GroupRepositoryURLProtocol: URLProtocol {
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
