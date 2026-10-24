import XCTest

final class AuthenticationEntryUITests: XCTestCase {
  func testFreshLaunchShowsEmailLoginAndLocalOnlyOptionWithoutAskingForKeys() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-mobile.auth.loginDeferred", "NO",
      "-mobile.supabase.projectURL", "",
      "-mobile.supabase.publishableKey", "",
      "-mobile.auth.lastEmail", "",
    ]
    app.launch()

    let emailField = app.textFields["authEmail"]
    XCTAssertTrue(emailField.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["continueWithoutLogin"].exists)

    let sendCodeButton = app.buttons["sendEmailOTP"]
    XCTAssertTrue(sendCodeButton.exists)
    XCTAssertFalse(sendCodeButton.isEnabled)
    XCTAssertFalse(app.textFields["supabaseProjectURL"].exists)
    XCTAssertFalse(app.textFields["supabasePublishableKey"].exists)
    XCTAssertFalse(app.textFields["connectAPIBaseURL"].exists)

    let developerSettings = app.descendants(matching: .any)["developerConnectionSettings"]
    #if DEBUG
      XCTAssertTrue(developerSettings.exists)
    #else
      XCTAssertFalse(developerSettings.exists)
    #endif
  }
}
