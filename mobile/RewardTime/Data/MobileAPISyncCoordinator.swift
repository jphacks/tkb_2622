import Combine
import Foundation

@MainActor
final class MobileAPISyncCoordinator: ObservableObject {
    @Published private(set) var errorMessage: String?

    func synchronize(
        refreshHomeIfNeeded: Bool = true,
        usage: () async throws -> Void,
        refreshHome: () async throws -> Void
    ) async {
        var firstError: Error?
        do {
            try await usage()
        } catch {
            firstError = error
        }

        if refreshHomeIfNeeded {
            do {
                try await refreshHome()
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError {
            errorMessage = (firstError as? LocalizedError)?.errorDescription
                ?? firstError.localizedDescription
        } else {
            errorMessage = nil
        }
    }
}
