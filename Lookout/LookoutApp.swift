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
        CloudSyncMonitor.shared.start()
        if LookoutStore.isDemo {
            LookoutDemoData.seed(into: LookoutStore.container.mainContext)
        } else if LookoutSchemaSeed.isRequested {
            LookoutSchemaSeed.seed(into: LookoutStore.container.mainContext)
        } else {
            LookoutSchemaSeed.cleanSelections(in: LookoutStore.container.mainContext)
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
                        BackgroundUpload.hold()
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

    /// iOS gives an app refresh about 30 seconds. Publishing and the upload
    /// that follows share this much of it; expiration covers a shorter grant.
    private static let budget: TimeInterval = 25

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
        let deadline = Date.now.addingTimeInterval(budget)
        let completion = Completion(task)
        let work = Task { @MainActor in
            // Publishing only saves on this device. Completing the task then
            // lets iOS suspend the app before the mirror has uploaded
            // anything, and the TV keeps yesterday's agenda until someone
            // opens the app. Hold the task until that upload has ended.
            switch await BoardPublisher.shared.publish(reason: "background refresh") {
            case .saved(let saved):
                let result = await CloudSyncMonitor.shared.waitForExport(
                    of: saved, timeout: deadline.timeIntervalSinceNow)
                completion.finish(success: result == .uploaded)
            case .skipped:
                completion.finish(success: true)
            case .failed:
                completion.finish(success: false)
            }
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }

    /// The work and the expiration handler race; the task must be completed
    /// exactly once, by whichever gets there first.
    nonisolated private final class Completion: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var done = false

        init(_ task: BGTask) { self.task = task }

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// A change made just before leaving the app is saved on this device at once,
/// but the Apple TV only sees it after the upload to iCloud, and iOS suspends
/// the app seconds after it leaves the screen. Asks for a little background
/// time, only while a publish or its upload is still under way, and gives it
/// back as soon as the upload ends.
enum BackgroundUpload {
    /// Inside the roughly 30 seconds iOS allows after leaving the foreground.
    private static let limit: TimeInterval = 20
    private static var current: Hold?

    static func hold() {
        let publisher = BoardPublisher.shared
        let sync = CloudSyncMonitor.shared
        guard current == nil, !LookoutStore.isDemo else { return }
        guard publisher.isBusy || publisher.lastSavedAt.map(sync.isAwaitingExport(of:)) == true else { return }

        let hold = Hold()
        current = hold
        let deadline = Date.now.addingTimeInterval(limit)
        let work = Task {
            await publisher.waitUntilIdle()
            if let saved = publisher.lastSavedAt {
                _ = await sync.waitForExport(of: saved, timeout: deadline.timeIntervalSinceNow)
            }
            hold.end()
        }
        hold.identifier = UIApplication.shared.beginBackgroundTask(withName: "Lookout upload") {
            work.cancel()
            hold.end()
        }
    }

    private final class Hold {
        var identifier = UIBackgroundTaskIdentifier.invalid
        private var ended = false

        func end() {
            guard !ended else { return }
            ended = true
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
            }
            if BackgroundUpload.current === self { BackgroundUpload.current = nil }
        }
    }
}
