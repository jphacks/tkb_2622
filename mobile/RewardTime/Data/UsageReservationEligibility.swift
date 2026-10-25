import Foundation

enum UsageReservationEligibility: Equatable {
    case allowed
    case insufficientBalance
    case invalidPendingRequest

    static func evaluate(
        selectedSeconds: Int,
        balanceSeconds: Int,
        pendingOperationID: String?,
        pendingSeconds: Int?
    ) -> Self {
        if let pendingOperationID {
            guard !pendingOperationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let pendingSeconds,
                  pendingSeconds > 0,
                  pendingSeconds == selectedSeconds else {
                return .invalidPendingRequest
            }
            // The reservation may already have been committed, reducing the
            // balance before the client received its response. Replaying the
            // same operation ID and duration is safe and must remain possible.
            return .allowed
        }

        guard selectedSeconds > 0 else { return .insufficientBalance }
        return selectedSeconds <= balanceSeconds ? .allowed : .insufficientBalance
    }
}
