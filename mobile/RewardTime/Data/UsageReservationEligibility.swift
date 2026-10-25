import Foundation

enum UsageReservationEligibility: Equatable {
    case allowed
    case insufficientBalance
    case invalidPendingRequest

    static func evaluate(
        selectedMinutes: Int,
        balanceMinutes: Int,
        pendingOperationID: String?,
        pendingSeconds: Int?
    ) -> Self {
        if let pendingOperationID {
            guard !pendingOperationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let pendingSeconds,
                  pendingSeconds > 0,
                  pendingSeconds.isMultiple(of: 60),
                  pendingSeconds / 60 == selectedMinutes else {
                return .invalidPendingRequest
            }
            // The reservation may already have been committed, reducing the
            // balance before the client received its response. Replaying the
            // same operation ID and duration is safe and must remain possible.
            return .allowed
        }

        guard selectedMinutes > 0 else { return .insufficientBalance }
        return selectedMinutes <= balanceMinutes ? .allowed : .insufficientBalance
    }
}
