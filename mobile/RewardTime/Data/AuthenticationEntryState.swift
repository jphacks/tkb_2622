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
    if hasValidSession {
      return businessUserReady ? .authenticated : .identitySyncRequired
    }
    return loginDeferred ? .localOnly : .welcome
  }
}
