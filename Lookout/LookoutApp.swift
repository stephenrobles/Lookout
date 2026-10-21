import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

/// The iPhone and iPad companion: reads calendars, reminders and HomeKit on
/// this device and publishes a board description through CloudKit for the
/// Apple TV to show.
@main
struct LookoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if LookoutStore.isDemo {
            LookoutDemoData.seed(into: LookoutStore.container.mainContext)
        }
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        BoardPublisher.shared.schedulePublish(after: 0.5)
                    case .background:
                        BackgroundRefresh.schedule()
                    default:
                        break
                    }
                }
        }
        .modelContainer(LookoutStore.container)
    }
}

/// Registers for CloudKit's silent "data changed" pushes so a config edited on
/// another iPhone or iPad lands here promptly. No permission prompt is involved.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !LookoutStore.isDemo {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }
}

/// Periodic republish while the app is not running, so the TV keeps showing
/// fresh events even if the phone is never opened. iOS decides the real
/// cadence; the request only sets the earliest time.
nonisolated enum BackgroundRefresh {
    static let identifier = "fm.beard.Lookout.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            await BoardPublisher.shared.publish(reason: "background refresh")
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
