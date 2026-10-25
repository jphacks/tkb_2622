import BackgroundTasks
import UIKit

@MainActor
enum GroupFocusWidgetBackgroundRefresh {
    static let taskIdentifier = "com.example.tkb2622.mobile.group-focus-refresh"

    static func schedule(isAuthenticated: Bool) {
        guard isAuthenticated else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        // Background refresh may be disabled. Foreground sync remains available in that case.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        let hasAccount = !UserDefaults.standard.bool(forKey: "mobile.auth.loginDeferred")
            && MobileAppConfiguration.makeAuthService()?.authenticatedUserID != nil
        schedule(isAuthenticated: hasAccount)
        await GroupFocusWidgetSyncCoordinator.shared.synchronize()
    }

    static func enterBackground(isAuthenticated: Bool) {
        schedule(isAuthenticated: isAuthenticated)
        guard isAuthenticated else { return }
        TransitionRefresh().start()
    }

    // Finish one last fetch when the user returns to the Home Screen, within iOS's time limit.
    @MainActor
    private final class TransitionRefresh {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        private var work: Task<Void, Never>?

        func start() {
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Group focus widget") {
                self.work?.cancel()
                self.finish()
            }
            guard identifier != .invalid else { return }
            work = Task {
                defer { finish() }
                await GroupFocusWidgetSyncCoordinator.shared.synchronize()
            }
        }

        private func finish() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
