import Foundation

struct MobileGroup: Decodable, Identifiable {
    struct Member: Decodable {
        let isCurrentUser: Bool

        private enum CodingKeys: String, CodingKey { case isCurrentUser }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
        }
    }

    let id: String
    let name: String
    let members: [Member]
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
