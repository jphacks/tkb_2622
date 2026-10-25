import Foundation

@MainActor
final class NotificationEndpointRegistrationGate {
  enum Decision: Equatable {
    case start
    case alreadyRegistered
    case inFlight
  }

  private let defaults: UserDefaults
  private var inFlight = Set<String>()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func beginRegistration(for fingerprint: String, force: Bool = false) -> Decision {
    guard !inFlight.contains(fingerprint) else { return .inFlight }
    let successKey = "mobile.apns.registration.succeeded.\(fingerprint)"
    if force {
      defaults.removeObject(forKey: successKey)
    } else if defaults.bool(forKey: successKey) {
      return .alreadyRegistered
    }
    inFlight.insert(fingerprint)
    return .start
  }

  func finishRegistration(for fingerprint: String, succeeded: Bool) {
    inFlight.remove(fingerprint)
    let successKey = "mobile.apns.registration.succeeded.\(fingerprint)"
    if succeeded {
      defaults.set(true, forKey: successKey)
    } else {
      defaults.removeObject(forKey: successKey)
    }
  }

  func invalidateRegistration(for fingerprint: String) {
    defaults.removeObject(forKey: "mobile.apns.registration.succeeded.\(fingerprint)")
  }
}
