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
        state = .loading

        do {
            state = .loaded(try await repository.fetchCurrentSnapshot())
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription
                ?? "APIへ接続できません。通信状態とAPI設定を確認してください。")
        }
    }

    func showPreview(_ snapshot: MobileHomeSnapshot) {
        state = .loaded(snapshot)
    }

    func showFailurePreview() {
        state = .failed("開発用の通信エラー表示です。")
    }
}
