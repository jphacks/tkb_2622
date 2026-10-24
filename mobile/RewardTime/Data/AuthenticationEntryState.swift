enum AuthenticationEntryState: Equatable {
  case checking
  case welcome
  case authenticated
  case localOnly
  case identitySyncRequired

  static func resolve(
    hasValidSession: Bool,
    businessUserReady: Bool,
    loginDeferred: Bool
  ) -> Self {
    if loginDeferred { return .localOnly }
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
