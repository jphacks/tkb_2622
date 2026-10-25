import Foundation

protocol UnderlyingErrorProviding {
    var underlyingError: Error { get }
}

enum UsageReservationFailurePolicy {
    /// Keep the operation ID unless the server response proves the request was rejected.
    /// A lost response or server error may follow a committed reservation, which must be replayed
    /// with its original idempotency key.
    static func shouldDiscardPendingOperation(after error: Error) -> Bool {
        if let wrapped = error as? UnderlyingErrorProviding {
            return shouldDiscardPendingOperation(after: wrapped.underlyingError)
        }
        guard let clientError = error as? ConnectJSONClient.ClientError else { return false }

        switch clientError {
        case .connect(let code):
            return [
                "already_exists",
                "failed_precondition",
                "invalid_argument",
                "not_found",
                "out_of_range",
                "permission_denied",
                "resource_exhausted",
                "unauthenticated",
                "unimplemented",
            ].contains(code)
        case .httpStatus(let status):
            return (400..<500).contains(status) && ![408, 425, 429].contains(status)
        case .missingAccessToken, .tokenProviderFailed, .invalidResponse, .unexpectedHealthStatus:
            return false
        }
    }
}
