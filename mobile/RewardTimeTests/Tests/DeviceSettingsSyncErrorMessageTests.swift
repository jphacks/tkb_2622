import XCTest
@testable import ConnectJSONClient

final class DeviceSettingsSyncErrorMessageTests: XCTestCase {
    func testPreservesConnectErrorCodeForDeviceSettingsFailure() {
        let message = DeviceSettingsSyncErrorMessage.describe(ConnectJSONClient.ClientError.connect(code: "internal"))

        XCTAssertTrue(message.contains("(internal)"))
    }

    func testUsesSafeFallbackForUnlocalizedError() {
        let message = DeviceSettingsSyncErrorMessage.describe(URLError(.notConnectedToInternet))

        XCTAssertEqual(message, "端末設定を同期できません。時間をおいて再試行してください。")
    }
}
