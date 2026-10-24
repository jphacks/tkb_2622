import XCTest
@testable import ConnectJSONClient

final class NotificationEndpointRegistrationFlowTests: XCTestCase {
    func testUnauthenticatedRefreshDoesNotRegisterOrRemoveEndpoint() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: false,
                permission: .allowed,
                token: "apns-token"
            ),
            .signInRequired
        )
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: false,
                permission: .denied,
                token: nil
            ),
            .signInRequired
        )
    }

    func testAuthenticatedRefreshChoosesRegistrationOrRemoval() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                permission: .allowed,
                token: "apns-token"
            ),
            .register(token: "apns-token")
        )
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                permission: .denied,
                token: nil
            ),
            .remove
        )
    }

    func testUnresolvedPermissionDoesNotRegisterAnAvailableToken() {
        XCTAssertEqual(
            NotificationEndpointSyncPolicy.resolve(
                isAuthenticated: true,
                permission: .notAllowed,
                token: "apns-token"
            ),
            .permissionRequired
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
