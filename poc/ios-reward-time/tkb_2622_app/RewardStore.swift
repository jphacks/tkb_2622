import Combine
import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var snapshot = RewardSnapshot.demo
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private let repository: any RewardRepository

    init(repository: any RewardRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            snapshot = try await repository.load()
        } catch {
            errorMessage = "報酬状態を読み込めませんでした。\(error.localizedDescription)"
        }
    }

    func redeem(minutes: Int) async {
        do {
            snapshot = try await repository.redeem(minutes: minutes, now: .now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}
