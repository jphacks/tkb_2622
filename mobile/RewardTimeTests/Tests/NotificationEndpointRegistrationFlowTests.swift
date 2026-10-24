import XCTest
@testable import ConnectJSONClient

final class NotificationEndpointRegistrationFlowTests: XCTestCase {
    func testUnauthenticatedRefreshDoesNotRegisterOrRemoveEndpoint() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: false,
                isAllowed: true,
                isDenied: false,
                token: "apns-token"
            ),
            .signInRequired
        )
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: false,
                isAllowed: false,
                isDenied: true,
                token: nil
            ),
            .signInRequired
        )
    }

    func testAuthenticatedRefreshChoosesRegistrationOrRemoval() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                isAllowed: true,
                isDenied: false,
                token: "apns-token"
            ),
            .register(token: "apns-token")
        )
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                isAllowed: false,
                isDenied: true,
                token: nil
            ),
            .remove
        )
    }

    func testDeviceIsRegisteredBeforeNotificationEndpoint() async throws {
        let steps = RegistrationSteps()

        try await NotificationEndpointRegistrationFlow.register(
            ensureDevice: { await steps.append("device") },
            registerEndpoint: { await steps.append("endpoint") }
        )

        let values = await steps.snapshot()
        XCTAssertEqual(values, ["device", "endpoint"])
    }

    func testDeviceRegistrationFailurePreventsEndpointRequest() async {
        let steps = RegistrationSteps()

        do {
            try await NotificationEndpointRegistrationFlow.register(
                ensureDevice: { throw RegistrationFailure.device },
                registerEndpoint: { await steps.append("endpoint") }
            )
            XCTFail("Expected device registration to fail")
        } catch RegistrationFailure.device {
            let values = await steps.snapshot()
            XCTAssertEqual(values, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum RegistrationFailure: Error {
    case device
}

private actor RegistrationSteps {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] { values }
}
