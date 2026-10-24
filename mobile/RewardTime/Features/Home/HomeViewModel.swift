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

    private let repository: any HomeRepository
    private var loadGeneration = 0

    var lastUpdatedTime: String {
        guard case .loaded(let snapshot) = state else { return "未同期" }
        return snapshot.lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    var lastUpdatedLabel: String {
        guard case .loaded(let snapshot) = state else { return "未同期" }
        return "\(snapshot.isSampleData ? "サンプル" : "同期") \(lastUpdatedTime)"
    }

    init(repository: any HomeRepository) {
        self.repository = repository
    }

    func load() async {
        loadGeneration += 1
        let requestGeneration = loadGeneration
        state = .loading

        do {
            let snapshot = try await repository.fetchCurrentSnapshot()
            guard requestGeneration == loadGeneration else { return }
            state = .loaded(snapshot)
        } catch {
            guard requestGeneration == loadGeneration else { return }
            state = .failed((error as? LocalizedError)?.errorDescription
                ?? "APIへ接続できません。通信状態とAPI設定を確認してください。")
        }
    }

}
