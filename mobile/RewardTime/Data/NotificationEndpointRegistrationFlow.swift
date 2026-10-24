enum NotificationEndpointRegistrationFlow {
    static func register(
        ensureDevice: () async throws -> Void,
        registerEndpoint: () async throws -> Void
    ) async throws {
        try await ensureDevice()
        try await registerEndpoint()
    }
}

enum NotificationEndpointSyncPolicy {
    enum Action: Equatable {
        case signInRequired
        case register(token: String)
        case requestAppleRegistration
        case remove
        case permissionRequired
    }

    static func resolve(
        isAuthenticated: Bool,
        isAllowed: Bool,
        isDenied: Bool,
        token: String?
    ) -> Action {
        guard isAuthenticated else { return .signInRequired }
        if isAllowed {
            guard let token, !token.isEmpty else { return .requestAppleRegistration }
            return .register(token: token)
        }
        return isDenied ? .remove : .permissionRequired
    }
}
