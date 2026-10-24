import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(MobileHomeSnapshot)
        case failed
    }

    @Published private(set) var state: State = .loading

    private let repository: any HomeRepository

    var lastUpdatedTime: String {
        guard case .loaded(let snapshot) = state else { return "未同期" }
        return snapshot.lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    init(repository: any HomeRepository) {
        self.repository = repository
    }

    func load() async {
        state = .loading

        do {
            state = .loaded(try await repository.fetchCurrentSnapshot())
        } catch {
            state = .failed
        }
    }

    func showPreview(_ snapshot: MobileHomeSnapshot) {
        state = .loaded(snapshot)
    }
}
