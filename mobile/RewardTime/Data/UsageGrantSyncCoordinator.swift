import Combine
import Foundation

@MainActor
final class UsageGrantSyncCoordinator: ObservableObject {
    @Published private(set) var errorMessage: String?

    func synchronize(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
