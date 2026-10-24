import Combine

@MainActor
final class GroupViewModel: ObservableObject {
    enum State {
        case loading
        case loaded([MobileGroup])
        case failed
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
            state = .failed
        }
    }
}
