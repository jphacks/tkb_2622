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
    private let sleep: (UInt64) async throws -> Void
    private var loadGeneration = 0
    private var isLoadingWorkStarts = false

    init(
        repository: any GroupRepository,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.repository = repository
        self.sleep = sleep
    }

    func load() async {
        guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled, requestGeneration == loadGeneration else { return }
            state = .loaded(groups)
            loadError = nil
        } catch {
            guard !Task.isCancelled, requestGeneration == loadGeneration else { return }
            let message = Self.failureMessage(for: error, operation: .listGroups)
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
                try await sleep(needsGroupReload ? 5_000_000_000 : 30_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if needsGroupReload {
                await load()
            }
        }
    }

    private var needsGroupReload: Bool {
        if case .failed = state { return true }
        return loadError != nil
    }

    func refreshWorkStarts() async {
        guard !Task.isCancelled, !isLoadingWorkStarts,
              case .loaded(let groups) = state,
              !groups.isEmpty else { return }
        isLoadingWorkStarts = true
        defer { isLoadingWorkStarts = false }
        do {
            let newEvents = try await repository.fetchWorkStarts()
            guard !Task.isCancelled else { return }
            workStartError = nil
            let knownIDs = Set(workStarts.map(\.id))
            workStarts = Array((newEvents.filter { !knownIDs.contains($0.id) } + workStarts)
                .sorted { $0.startedAt.date > $1.startedAt.date }
                .prefix(30))
        } catch {
            guard !Task.isCancelled else { return }
            workStartError = GroupAPIErrorMessage.describe(error, operation: .workStartFeed)
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

    private static func failureMessage(
        for error: Error,
        operation: GroupAPIErrorMessage.Operation
    ) -> String {
        switch error {
        case GroupRepositoryError.missingConfiguration:
            return "設定タブでSupabase Project URL・公開用キー・API URLを設定してください。 (API: \(operation.rawValue))"
        case GroupRepositoryError.invalidConfiguration:
            return "設定タブのSupabase接続情報とAPI URLを確認してください。 (API: \(operation.rawValue))"
        case let clientError as ConnectJSONClient.ClientError:
            return GroupAPIErrorMessage.describe(clientError, operation: operation)
        case let error as LocalizedError:
            return GroupAPIErrorMessage.describe(error, operation: operation)
        default:
            return GroupAPIErrorMessage.describe(error, operation: operation)
        }
    }
}
