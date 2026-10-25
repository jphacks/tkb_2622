import XCTest
@testable import ConnectJSONClient

final class GroupAPIErrorMessageTests: XCTestCase {
    func testUnimplementedConnectRouteIsDistinguishedFromMissingGroupData() {
        let message = GroupAPIErrorMessage.describe(.connect(code: "unimplemented"))

        XCTAssertTrue(message.contains("グループAPIがありません"))
        XCTAssertTrue(message.contains("backend"))
    }

    func testInternalErrorRequestsLogsAndMigrationCheckWithoutAssumingCause() {
        let message = GroupAPIErrorMessage.describe(.connect(code: "internal"))

        XCTAssertTrue(message.contains("APIログ"))
        XCTAssertTrue(message.contains("migration"))
        XCTAssertTrue(message.contains("internal"))
    }

    func testNotFoundAndUnauthenticatedErrorsHaveSeparateGuidance() {
        let notFound = GroupAPIErrorMessage.describe(.connect(code: "not_found"))
        let unauthenticated = GroupAPIErrorMessage.describe(.connect(code: "unauthenticated"))

        XCTAssertTrue(notFound.contains("見つかりません"))
        XCTAssertTrue(notFound.contains("not_found"))
        XCTAssertTrue(unauthenticated.contains("ログイン"))
        XCTAssertTrue(unauthenticated.contains("unauthenticated"))
    }

    func testRawHttp404StillExplainsMissingBackendRoute() {
        XCTAssertTrue(
            GroupAPIErrorMessage.describe(.httpStatus(404)).contains("グループAPIがありません")
        )
    }

    func testGroupActionErrorWrapperKeepsConnectGuidance() {
        let error: Error = ConnectJSONClient.ClientError.connect(code: "unauthenticated")

        XCTAssertTrue(GroupAPIErrorMessage.describe(error).contains("再ログイン"))
    }

    func testFailedPreconditionGuidanceIsSpecificToAcceptInvitation() {
        let error = ConnectJSONClient.ClientError.connect(code: "failed_precondition")

        let accept = GroupAPIErrorMessage.describe(error, operation: .acceptInvitation)
        let create = GroupAPIErrorMessage.describe(error, operation: .createInvitation)
        let leave = GroupAPIErrorMessage.describe(error, operation: .leaveGroup)

        XCTAssertTrue(accept.contains("招待リンクは期限切れ"))
        XCTAssertFalse(create.contains("期限切れ"))
        XCTAssertFalse(leave.contains("期限切れ"))
        XCTAssertTrue(create.contains("CreateInvitation"))
        XCTAssertTrue(leave.contains("LeaveGroup"))
    }

    func testGroupErrorIncludesOperationNameForBackendLogMatching() {
        let message = GroupAPIErrorMessage.describe(
            ConnectJSONClient.ClientError.connect(code: "internal"),
            operation: .createGroup
        )

        XCTAssertTrue(message.contains("CreateGroup"))
        XCTAssertTrue(message.contains("internal"))
        XCTAssertTrue(message.contains("APIログ"))
    }
}
