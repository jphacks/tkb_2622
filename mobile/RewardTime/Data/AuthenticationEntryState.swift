enum AuthenticationEntryState: Equatable {
  case checking
  case welcome
  case authenticated
  case localOnly
  case identitySyncRequired

  static func resolve(
    hasValidSession: Bool,
    businessUserReady: Bool,
    loginDeferred: Bool,
    sessionCheckFailed: Bool = false
  ) -> Self {
    if loginDeferred { return .localOnly }
    if sessionCheckFailed { return .identitySyncRequired }
    if hasValidSession {
      return businessUserReady ? .authenticated : .identitySyncRequired
    }
    return .welcome
  }

  static func needsBusinessIdentitySync(currentState: Self, loginDeferred: Bool) -> Bool {
    guard !loginDeferred else { return false }
    return currentState == .checking || currentState == .identitySyncRequired
  }
}

struct AuthenticationSessionRestoreGate {
  private(set) var hasStarted = false

  mutating func begin() -> Bool {
    guard !hasStarted else { return false }
    hasStarted = true
    return true
  }
}

enum IdentitySyncOrigin {
  case automaticSessionRestore
  case userInitiated

  var notifiesRootAuthenticationState: Bool {
    switch self {
    case .automaticSessionRestore: false
    case .userInitiated: true
    }
  }
}
