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
    @Published private(set) var loadError: String?
    @Published private(set) var workStarts: [MobileGroupWorkStart] = []
    @Published private(set) var workStartError: String?
    private let repository: any GroupRepository
    private var loadGeneration = 0
    private var isLoadingWorkStarts = false

    init(repository: any GroupRepository) {
        self.repository = repository
    }

    func load() async {
        loadGeneration += 1
        let requestGeneration = loadGeneration
        let previousGroups: [MobileGroup]?
        if case .loaded(let groups) = state {
            previousGroups = groups
        } else {
            previousGroups = nil
            state = .loading
        }
        loadError = nil
        do {
            let groups = try await repository.fetchGroups()
            guard requestGeneration == loadGeneration else { return }
            state = .loaded(groups)
            loadError = nil
        } catch {
            guard requestGeneration == loadGeneration else { return }
            let message = Self.failureMessage(for: error)
            if let previousGroups {
                state = .loaded(previousGroups)
                loadError = message
            } else {
                state = .failed(message)
            }
        }
    }

    func runWorkStartPolling() async {
        await load()
        while !Task.isCancelled {
            await refreshWorkStarts()
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                return
            }
        }
    }

    func refreshWorkStarts() async {
        guard !isLoadingWorkStarts,
              case .loaded(let groups) = state,
              !groups.isEmpty else { return }
        isLoadingWorkStarts = true
        defer { isLoadingWorkStarts = false }
        do {
            let newEvents = try await repository.fetchWorkStarts()
            workStartError = nil
            let knownIDs = Set(workStarts.map(\.id))
            workStarts = Array((newEvents.filter { !knownIDs.contains($0.id) } + workStarts)
                .sorted { $0.startedAt.date > $1.startedAt.date }
                .prefix(30))
        } catch {
            workStartError = GroupAPIErrorMessage.describe(error)
        }
    }

    func createGroup(name: String, operationID: String) async throws -> MobileGroup {
        let group = try await repository.createGroup(name: name, operationID: operationID)
        if case .loaded(let groups) = state {
            state = .loaded(groups.filter { $0.id != group.id } + [group])
        } else {
            state = .loaded([group])
        }
        loadError = nil
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
        loadError = nil
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
        case let clientError as ConnectJSONClient.ClientError:
            return GroupAPIErrorMessage.describe(clientError)
        case let error as LocalizedError:
            return error.errorDescription ?? "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
        default:
            return "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
        }
    }
}
