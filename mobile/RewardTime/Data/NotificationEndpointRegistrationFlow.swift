enum NotificationEndpointRegistrationFlow {
    static func register(
        ensureDevice: () async throws -> Void,
        registerEndpoint: () async throws -> Void
    ) async throws {
        try await ensureDevice()
        try await registerEndpoint()
    }
}
