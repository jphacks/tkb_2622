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

  func testNotificationToolbarOpensSettingsInLocalOnlyMode() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-mobile.auth.loginDeferred", "NO",
      "-mobile.supabase.projectURL", "",
      "-mobile.supabase.publishableKey", "",
      "-mobile.auth.lastEmail", "",
    ]
    app.launch()

    let continueButton = app.buttons["continueWithoutLogin"]
    XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
    continueButton.tap()

    let notificationButton = app.buttons["notificationToolbarButton"]
    XCTAssertTrue(notificationButton.waitForExistence(timeout: 10))
    notificationButton.tap()

    XCTAssertTrue(app.navigationBars["通知"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["通知先をサーバーと同期するにはログインしてください。"].exists)
  }

  func testSettingsTabOpensInLocalOnlyMode() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-mobile.auth.loginDeferred", "NO",
      "-mobile.supabase.projectURL", "",
      "-mobile.supabase.publishableKey", "",
      "-mobile.auth.lastEmail", "",
    ]
    app.launch()

    let continueButton = app.buttons["continueWithoutLogin"]
    XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
    continueButton.tap()

    let settingsTab = app.tabBars.buttons["設定"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
    settingsTab.tap()

    XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["制限モード"].exists)
  }
}
