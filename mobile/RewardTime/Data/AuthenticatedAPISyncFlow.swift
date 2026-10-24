enum AuthenticatedAPISyncFlow {
    static func run(
        isAuthenticated: Bool,
        operation: () async throws -> Void
    ) async throws {
        guard isAuthenticated else { return }
        try await operation()
    }
}
