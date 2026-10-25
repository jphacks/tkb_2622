import XCTest
@testable import ConnectJSONClient

final class NotificationEndpointRegistrationGateTests: XCTestCase {
    private var defaultsSuite: String!

    override func tearDown() {
        if let defaultsSuite {
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        }
        super.tearDown()
    }

    @MainActor
    func testRefreshDoesNotRepeatSuccessfulRegistrationButExplicitSyncDoes() {
        let defaults = makeDefaults()
        let gate = NotificationEndpointRegistrationGate(defaults: defaults)
        let key = "test-registration-fingerprint"

        XCTAssertEqual(gate.beginRegistration(for: key), .start)
        XCTAssertEqual(gate.beginRegistration(for: key), .inFlight)
        gate.finishRegistration(for: key, succeeded: true)

        XCTAssertEqual(gate.beginRegistration(for: key), .alreadyRegistered)
        XCTAssertEqual(gate.beginRegistration(for: key, force: true), .start)
    }

    @MainActor
    func testFailedRegistrationCanBeRetried() {
        let defaults = makeDefaults()
        let gate = NotificationEndpointRegistrationGate(defaults: defaults)
        let key = "test-registration-fingerprint"

        XCTAssertEqual(gate.beginRegistration(for: key), .start)
        gate.finishRegistration(for: key, succeeded: false)
        XCTAssertEqual(gate.beginRegistration(for: key), .start)
    }

    private func makeDefaults() -> UserDefaults {
        defaultsSuite = "NotificationEndpointRegistrationGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        return defaults
    }
}
