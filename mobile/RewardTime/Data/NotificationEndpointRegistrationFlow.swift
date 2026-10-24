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
    enum Permission: Equatable {
        case allowed
        case denied
        case notAllowed
    }

    enum Action: Equatable {
        case signInRequired
        case register(token: String)
        case requestAppleRegistration
        case remove
        case permissionRequired
    }

    static func resolve(
        isAuthenticated: Bool,
        permission: Permission,
        token: String?
    ) -> Action {
        guard isAuthenticated else { return .signInRequired }
        switch permission {
        case .allowed:
            guard let token, !token.isEmpty else { return .requestAppleRegistration }
            return .register(token: token)
        case .denied:
            return .remove
        case .notAllowed:
            return .permissionRequired
        }
    }
}
