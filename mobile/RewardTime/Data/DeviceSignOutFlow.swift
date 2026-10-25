enum DeviceSignOutFlow {
    static func perform(
        revokeDevice: () async throws -> Void,
        signOutLocally: () async throws -> Void
    ) async throws {
        try await revokeDevice()
        try await signOutLocally()
    }
}
