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
}
