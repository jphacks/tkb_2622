import SwiftUI
import UIKit
import UserNotifications

final class RewardTimeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "mobile.apns.token")
        NotificationCenter.default.post(name: .mobileAPNsTokenReceived, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .mobileAPNsRegistrationFailed, object: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}

@main
struct RewardTimeApp: App {
    @UIApplicationDelegateAdaptor(RewardTimeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .backgroundTask(.appRefresh(GroupFocusWidgetBackgroundRefresh.taskIdentifier)) {
            await GroupFocusWidgetBackgroundRefresh.run()
        }
    }
}
