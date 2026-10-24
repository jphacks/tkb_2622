import Foundation

struct MobileGroup: Decodable, Identifiable {
    struct Member: Decodable {
        let isCurrentUser: Bool
        let displayName: String
        let joinedAt: GroupProtoTimestamp?

        private enum CodingKeys: String, CodingKey { case isCurrentUser, displayName, joinedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "メンバー"
            joinedAt = try container.decodeIfPresent(GroupProtoTimestamp.self, forKey: .joinedAt)
        }
    }

    let id: String
    let name: String
    let createdAt: GroupProtoTimestamp?
    let members: [Member]

    private enum CodingKeys: String, CodingKey { case id, name, createdAt, members }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "グループ"
        createdAt = try container.decodeIfPresent(GroupProtoTimestamp.self, forKey: .createdAt)
        members = try container.decodeIfPresent([Member].self, forKey: .members) ?? []
    }
}

struct GroupProtoTimestamp: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) ?? Self.withoutFractionalSeconds.date(from: text) {
            self.date = date
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an RFC 3339 group timestamp")
        }
    }

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

protocol GroupRepository {
    func fetchGroups() async throws -> [MobileGroup]
    func fetchWorkStarts() async throws -> [MobileGroupWorkStart]
    func createGroup(name: String, operationID: String) async throws -> MobileGroup
    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation
    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup
    func leaveGroup(groupID: String, operationID: String) async throws -> Bool
}

struct MobileGroupWorkStart: Decodable, Identifiable {
    let eventID: String
    let startedAt: GroupProtoTimestamp

    var id: String { eventID }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case startedAt = "started_at"
    }
}

struct MobileGroupInvitation {
    let id: String
    let token: String
    let expiresAt: GroupProtoTimestamp
}

enum GroupInvitationLink {
    static let scheme = "rewardtime"
    static let host = "invite"

    static func make(token: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    static func token(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value
    }
}

struct APIGroupRepository: GroupRepository {
    private struct EmptyRequest: Encodable {}
    private struct CreateGroupRequest: Encodable {
        let operationId: String
        let name: String
    }

    private struct CreateGroupResponse: Decodable {
        let group: MobileGroup
    }

    private struct CreateInvitationRequest: Encodable {
        let operationId: String
        let groupId: String
    }

    private struct CreateInvitationResponse: Decodable {
        let invitationId: String
        let token: String
        let expiresAt: GroupProtoTimestamp
    }

    private struct AcceptInvitationRequest: Encodable {
        let operationId: String
        let token: String
    }

    private struct AcceptInvitationResponse: Decodable {
        let group: MobileGroup
    }

    private struct LeaveGroupRequest: Encodable {
        let operationId: String
        let groupId: String
    }

    private struct LeaveGroupResponse: Decodable {
        let groupDeleted: Bool
    }

    private struct ListGroupsResponse: Decodable {
        let groups: [MobileGroup]

        private enum CodingKeys: String, CodingKey { case groups }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groups = try container.decodeIfPresent([MobileGroup].self, forKey: .groups) ?? []
        }
    }

    private struct WorkStartsResponse: Decodable {
        let events: [MobileGroupWorkStart]
        let nextStartedAt: String?
        let nextEventID: String?

        private enum CodingKeys: String, CodingKey {
            case events
            case nextStartedAt = "next_started_at"
            case nextEventID = "next_event_id"
        }
    }

    private struct WorkStartCursor: Codable {
        let startedAt: String
        let eventID: String?
    }

    private static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private let client: ConnectJSONClient
    private let baseURL: URL
    private let auth: SupabaseAuthService

    init(baseURL: URL, auth: SupabaseAuthService) {
        self.baseURL = baseURL
        self.auth = auth
        client = ConnectJSONClient(baseURL: baseURL, tokenProvider: auth)
    }

    func fetchGroups() async throws -> [MobileGroup] {
        let response: ListGroupsResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "ListGroups",
            requestBody: EmptyRequest(),
            responseType: ListGroupsResponse.self
        )
        return response.groups
    }

    func fetchWorkStarts() async throws -> [MobileGroupWorkStart] {
        let userID = auth.authenticatedUserID ?? "unknown"
        let apiLocation = "\(baseURL.scheme ?? "http")-\(baseURL.host ?? "api")-\(baseURL.port ?? 0)"
        let cursorKey = "mobile.group.work-start-cursor.\(apiLocation).\(userID)"
        let defaults = UserDefaults.standard
        let cursor = defaults.data(forKey: cursorKey)
            .flatMap { try? JSONDecoder().decode(WorkStartCursor.self, from: $0) }
            ?? WorkStartCursor(startedAt: Self.rfc3339String(from: Date()), eventID: nil)

        var queryItems = [URLQueryItem(name: "after_started_at", value: cursor.startedAt)]
        if let eventID = cursor.eventID {
            queryItems.append(URLQueryItem(name: "after_event_id", value: eventID))
        }
        queryItems.append(URLQueryItem(name: "page_size", value: "50"))

        let response: WorkStartsResponse = try await client.get(
            path: "v1/group/work-starts",
            queryItems: queryItems,
            responseType: WorkStartsResponse.self
        )
        if let nextStartedAt = response.nextStartedAt {
            let nextCursor = WorkStartCursor(startedAt: nextStartedAt, eventID: response.nextEventID)
            if let data = try? JSONEncoder().encode(nextCursor) {
                defaults.set(data, forKey: cursorKey)
            }
        } else if defaults.data(forKey: cursorKey) == nil,
                  let data = try? JSONEncoder().encode(cursor) {
            defaults.set(data, forKey: cursorKey)
        }
        return response.events
    }

    func createGroup(name: String, operationID: String) async throws -> MobileGroup {
        let response: CreateGroupResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "CreateGroup",
            requestBody: CreateGroupRequest(operationId: operationID, name: name),
            responseType: CreateGroupResponse.self
        )
        return response.group
    }

    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation {
        let response: CreateInvitationResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "CreateInvitation",
            requestBody: CreateInvitationRequest(operationId: operationID, groupId: groupID),
            responseType: CreateInvitationResponse.self
        )
        return MobileGroupInvitation(id: response.invitationId, token: response.token, expiresAt: response.expiresAt)
    }

    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup {
        let response: AcceptInvitationResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "AcceptInvitation",
            requestBody: AcceptInvitationRequest(operationId: operationID, token: token),
            responseType: AcceptInvitationResponse.self
        )
        return response.group
    }

    func leaveGroup(groupID: String, operationID: String) async throws -> Bool {
        let response: LeaveGroupResponse = try await client.call(
            service: "group.v1.GroupService",
            method: "LeaveGroup",
            requestBody: LeaveGroupRequest(operationId: operationID, groupId: groupID),
            responseType: LeaveGroupResponse.self
        )
        return response.groupDeleted
    }
}

struct ConfiguredGroupRepository: GroupRepository {
    func fetchGroups() async throws -> [MobileGroup] {
        try await repository().fetchGroups()
    }

    func fetchWorkStarts() async throws -> [MobileGroupWorkStart] {
        try await repository().fetchWorkStarts()
    }

    func createGroup(name: String, operationID: String) async throws -> MobileGroup {
        try await repository().createGroup(name: name, operationID: operationID)
    }

    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation {
        try await repository().createInvitation(groupID: groupID, operationID: operationID)
    }

    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup {
        try await repository().acceptInvitation(token: token, operationID: operationID)
    }

    func leaveGroup(groupID: String, operationID: String) async throws -> Bool {
        try await repository().leaveGroup(groupID: groupID, operationID: operationID)
    }

    private func repository() throws -> APIGroupRepository {
        let projectURLText = MobileAppConfiguration.supabaseProjectURL ?? ""
        let publishableKey = MobileAppConfiguration.supabasePublishableKey ?? ""
        let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL ?? ""

        guard !projectURLText.isEmpty, !publishableKey.isEmpty else {
            throw GroupRepositoryError.missingConfiguration
        }
        guard let projectURL = Self.validatedURL(projectURLText),
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret"),
              let apiBaseURL = Self.validatedURL(apiBaseURLText) else {
            throw GroupRepositoryError.invalidConfiguration
        }

        let auth = SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        return APIGroupRepository(baseURL: apiBaseURL, auth: auth)
    }

    private static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

enum GroupRepositoryError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "設定タブでSupabase接続情報を設定し、ログインしてください。"
        case .invalidConfiguration:
            "Supabase接続情報とbackend API URLを確認してください。"
        }
    }
}
