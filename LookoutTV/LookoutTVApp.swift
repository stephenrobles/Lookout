import SwiftData
import SwiftUI
import UIKit

/// The Apple TV app: a read-only status board. Calendar and reminder records
/// arrive through CloudKit from the iPhone app; weather and HomeKit are read
/// here, on the TV itself.
@main
struct LookoutTVApp: App {
    @UIApplicationDelegateAdaptor(TVAppDelegate.self) private var appDelegate

    init() {
        if LookoutStore.isDemo {
            LookoutDemoData.seed(into: LookoutStore.container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            BoardView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // A wall display should not go to sleep while the board is up.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
        .modelContainer(LookoutStore.container)
    }
}

/// CloudKit's silent "data changed" pushes are only delivered to apps that
/// registered; the mirroring container imports on its own once one lands.
final class TVAppDelegate: NSObject, UIApplicationDelegate {
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
