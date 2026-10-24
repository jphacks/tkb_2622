import Foundation
import XCTest
@testable import ConnectJSONClient

final class UsageReservationFailurePolicyTests: XCTestCase {
    func testPendingReservationCanBeRetriedAfterItsBalanceWasDebited() {
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 0,
                pendingOperationID: "operation-1",
                pendingSeconds: 600
            ),
            .allowed
        )
    }

    func testPendingReservationRetryRequiresTheOriginalDurationAndValidMetadata() {
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 15,
                balanceMinutes: 0,
                pendingOperationID: "operation-1",
                pendingSeconds: 600
            ),
            .invalidPendingRequest
        )
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 30,
                pendingOperationID: "operation-1",
                pendingSeconds: nil
            ),
            .invalidPendingRequest
        )
    }

    func testNewReservationStillRequiresEnoughBalance() {
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 5,
                pendingOperationID: nil,
                pendingSeconds: nil
            ),
            .insufficientBalance
        )
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 10,
                balanceMinutes: 10,
                pendingOperationID: nil,
                pendingSeconds: nil
            ),
            .allowed
        )
        XCTAssertEqual(
            UsageReservationEligibility.evaluate(
                selectedMinutes: 0,
                balanceMinutes: 0,
                pendingOperationID: nil,
                pendingSeconds: nil
            ),
            .insufficientBalance
        )
    }

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
        XCTAssertTrue(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: WrappedAPIError(underlyingError: ConnectJSONClient.ClientError.connect(code: "failed_precondition"))
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
        XCTAssertFalse(
            UsageReservationFailurePolicy.shouldDiscardPendingOperation(
                after: WrappedAPIError(underlyingError: ConnectJSONClient.ClientError.connect(code: "internal"))
            )
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

private struct WrappedAPIError: Error, UnderlyingErrorProviding {
    let underlyingError: Error
}
