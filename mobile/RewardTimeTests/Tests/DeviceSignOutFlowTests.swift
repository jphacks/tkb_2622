import XCTest
@testable import ConnectJSONClient

final class DeviceSignOutFlowTests: XCTestCase {
    func testRevokesDeviceBeforeSigningOutLocally() async throws {
        var events: [String] = []

        try await DeviceSignOutFlow.perform(
            revokeDevice: { events.append("revoke") },
            signOutLocally: { events.append("signOut") }
        )

        XCTAssertEqual(events, ["revoke", "signOut"])
    }

    func testDoesNotSignOutLocallyWhenDeviceRevocationFails() async {
        var didSignOutLocally = false

        do {
            try await DeviceSignOutFlow.perform(
                revokeDevice: { throw TestFailure.revocation },
                signOutLocally: { didSignOutLocally = true }
            )
            XCTFail("Expected device revocation to fail")
        } catch TestFailure.revocation {
            XCTAssertFalse(didSignOutLocally)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum TestFailure: Error {
    case revocation
}
