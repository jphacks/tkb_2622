import Foundation
import XCTest
@testable import ConnectJSONClient

final class UsageReservationFailurePolicyTests: XCTestCase {
    func testDefinitiveClientRejectionsCanDiscardPendingOperation() {
        XCTAssertTrue(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.connect(code: "failed_precondition")
            )
        )
        XCTAssertTrue(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.httpStatus(409)
            )
        )
    }

    func testAmbiguousServerAndTransportResponsesKeepPendingOperation() {
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.connect(code: "internal")
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.httpStatus(502)
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.invalidResponse
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.missingAccessToken
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(after: URLError(.timedOut))
        )
    }

    func testRateLimitsAndTimeoutLikeResponsesKeepTheOriginalRequest() {
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.httpStatus(408)
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.httpStatus(429)
            )
        )
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: ConnectJSONClient.ClientError.connect(code: "unavailable")
            )
        )
    }
}
