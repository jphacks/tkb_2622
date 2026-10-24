import XCTest
@testable import ConnectJSONClient

final class AuthenticationEntryStateTests: XCTestCase {
    func testAuthenticatedEntryRequiresSuccessfulBusinessUserSync() {
        XCTAssertEqual(
            AuthenticationEntryState.resolve(hasValidSession: true, businessUserReady: false, loginDeferred: false),
            .identitySyncRequired
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(hasValidSession: true, businessUserReady: true, loginDeferred: false),
            .authenticated
        )
    }

    func testFirstLaunchAndDeferredLoginChooseExpectedEntry() {
        XCTAssertEqual(
            AuthenticationEntryState.resolve(hasValidSession: false, businessUserReady: false, loginDeferred: false),
            .welcome
        )
        XCTAssertEqual(
            AuthenticationEntryState.resolve(hasValidSession: false, businessUserReady: false, loginDeferred: true),
            .localOnly
        )
    }
}
