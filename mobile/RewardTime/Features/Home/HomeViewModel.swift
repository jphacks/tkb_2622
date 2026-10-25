import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(MobileHomeSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var refreshError: String?

    private let repository: any HomeRepository
    private var loadGeneration = 0

    init(repository: any HomeRepository) {
        self.repository = repository
    }

    func load() async {
        _ = await fetchSnapshot(preserveLoadedState: false)
    }

    func refresh() async -> Bool {
        await fetchSnapshot(preserveLoadedState: true)
    }

    private func fetchSnapshot(preserveLoadedState: Bool) async -> Bool {
        let hadLoadedState: Bool
        if case .loaded = state {
            hadLoadedState = true
        } else {
            hadLoadedState = false
        }

        loadGeneration += 1
        let requestGeneration = loadGeneration
        if !preserveLoadedState || !hadLoadedState {
            state = .loading
        }
        refreshError = nil

        do {
            let snapshot = try await repository.fetchCurrentSnapshot()
            guard requestGeneration == loadGeneration else { return false }
            state = .loaded(snapshot)
            return true
        } catch {
            guard requestGeneration == loadGeneration else { return false }
            let message = (error as? LocalizedError)?.errorDescription
                ?? "APIへ接続できません。通信状態とAPI設定を確認してください。"
            if preserveLoadedState && hadLoadedState {
                refreshError = message
                return false
            }
            state = .failed(message)
            return false
        }
    }

}
