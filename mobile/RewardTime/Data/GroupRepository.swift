import Foundation

struct MobileGroup: Decodable, Identifiable {
    struct Member: Decodable {
        let isCurrentUser: Bool
        let joinedAt: GroupProtoTimestamp?

        private enum CodingKeys: String, CodingKey { case isCurrentUser, joinedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
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
}

struct APIGroupRepository: GroupRepository {
    private struct EmptyRequest: Encodable {}
    private struct ListGroupsResponse: Decodable {
        let groups: [MobileGroup]

        private enum CodingKeys: String, CodingKey { case groups }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groups = try container.decodeIfPresent([MobileGroup].self, forKey: .groups) ?? []
        }
    }

    private let client: ConnectJSONClient

    init(baseURL: URL, auth: any AccessTokenProviding) {
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
}

struct ConfiguredGroupRepository: GroupRepository {
    func fetchGroups() async throws -> [MobileGroup] {
        let defaults = UserDefaults.standard
        let projectURLText = defaults.string(forKey: "mobile.supabase.projectURL") ?? ""
        let publishableKey = defaults.string(forKey: "mobile.supabase.publishableKey") ?? ""
        let apiBaseURLText = defaults.string(forKey: "mobile.api.baseURL") ?? "http://127.0.0.1:8080"

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
        return try await APIGroupRepository(baseURL: apiBaseURL, auth: auth).fetchGroups()
    }

    private static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

enum GroupRepositoryError: Error {
    case missingConfiguration
    case invalidConfiguration
}
