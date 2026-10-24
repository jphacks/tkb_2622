import Combine
import Foundation

@MainActor
final class GroupViewModel: ObservableObject {
    enum State {
        case loading
        case loaded([MobileGroup])
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private let repository: any GroupRepository

    init(repository: any GroupRepository) {
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.fetchGroups())
        } catch {
            state = .failed(Self.failureMessage(for: error))
        }
    }

    func createGroup(name: String, operationID: String) async throws -> MobileGroup {
        let group = try await repository.createGroup(name: name, operationID: operationID)
        if case .loaded(let groups) = state {
            state = .loaded(groups.filter { $0.id != group.id } + [group])
        } else {
            state = .loaded([group])
        }
        return group
    }

    func createInvitation(groupID: String, operationID: String) async throws -> MobileGroupInvitation {
        try await repository.createInvitation(groupID: groupID, operationID: operationID)
    }

    func acceptInvitation(token: String, operationID: String) async throws -> MobileGroup {
        let group = try await repository.acceptInvitation(token: token, operationID: operationID)
        if case .loaded(let groups) = state {
            state = .loaded(groups.filter { $0.id != group.id } + [group])
        } else {
            state = .loaded([group])
        }
        return group
    }

    func leaveGroup(groupID: String, operationID: String) async throws -> Bool {
        let groupDeleted = try await repository.leaveGroup(groupID: groupID, operationID: operationID)
        if case .loaded(let groups) = state {
            state = .loaded(groups.filter { $0.id != groupID })
        }
        return groupDeleted
    }

    private static func failureMessage(for error: Error) -> String {
        switch error {
        case GroupRepositoryError.missingConfiguration:
            return "設定タブでSupabase Project URL・公開用キー・API URLを設定してください。"
        case GroupRepositoryError.invalidConfiguration:
            return "設定タブのSupabase接続情報とAPI URLを確認してください。"
        case ConnectJSONClient.ClientError.httpStatus(404):
            return "接続先のbackendにグループAPIがありません。backendを最新版に更新して再起動してください。"
        case ConnectJSONClient.ClientError.connect(code: "internal"):
            return "backend内部エラーです。グループ用DBマイグレーションが適用済みか確認してください。"
        case ConnectJSONClient.ClientError.connect(code: "failed_precondition"):
            return "業務User登録が未完了です。設定タブでアカウント接続を再確認してください。"
        case let error as LocalizedError:
            return error.errorDescription ?? "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
        default:
            return "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
        }
    }
}
