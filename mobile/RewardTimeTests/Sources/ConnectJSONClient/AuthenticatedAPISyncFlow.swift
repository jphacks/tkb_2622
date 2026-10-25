enum AuthenticatedAPISyncFlow {
    @discardableResult
    static func run(
        isAuthenticated: Bool,
        operation: () async throws -> Void
    ) async throws -> Bool {
        guard isAuthenticated else { return false }
        try await operation()
        return true
    }
}
