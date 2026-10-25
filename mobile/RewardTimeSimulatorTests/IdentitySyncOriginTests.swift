import XCTest
@testable import RewardTime

final class IdentitySyncOriginTests: XCTestCase {
    func testAutomaticSessionRestoreDoesNotRestartRootAuthenticationFlow() {
        XCTAssertFalse(IdentitySyncOrigin.automaticSessionRestore.notifiesRootAuthenticationState)
    }

    func testUserInitiatedIdentitySyncNotifiesRootAuthenticationFlow() {
        XCTAssertTrue(IdentitySyncOrigin.userInitiated.notifiesRootAuthenticationState)
    }
}
