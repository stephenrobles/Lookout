import Foundation
import SwiftData

/// The one SwiftData stack each app uses. The iPhone writes, the Apple TV
/// reads, and CloudKit's private database carries records between them.
nonisolated enum LookoutStore {
    static let cloudContainerIdentifier = "iCloud.fm.beard.Lookout"

    static let schema = Schema([BoardConfig.self, AgendaEvent.self, ReminderItem.self])

    /// `-LookoutDemo` runs on an in-memory store seeded with sample content and
    /// CloudKit switched off, so demo data can never sync anywhere.
    static var isDemo: Bool {
        CommandLine.arguments.contains("-LookoutDemo")
    }

    /// True when no persistent store could be opened and the app fell back to
    /// memory. The TV shows a relaunch hint instead of an empty board.
    nonisolated(unsafe) private(set) static var startupUnavailable = false

    /// tvOS only guarantees writable space under Caches, and may purge it. That
    /// is fine for a read-only sync peer: it re-downloads on next launch.
    private static var storeURL: URL? {
        #if os(tvOS)
        guard let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true) else { return nil }
        #if DEBUG
        let directory = caches.appending(path: "Development", directoryHint: .isDirectory)
        #else
        let directory = caches.appending(path: "Lookout", directoryHint: .isDirectory)
        #endif
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appending(path: "Lookout.store")
        } catch {
            return nil
        }
        #else
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        #if DEBUG
        let directory = support.appending(path: "Development", directoryHint: .isDirectory)
        #else
        let directory = support.appending(path: "Lookout", directoryHint: .isDirectory)
        #endif
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appending(path: "Lookout.store")
        } catch {
            return nil
        }
        #endif
    }

    static let container: ModelContainer = {
        if isDemo {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                            allowsSave: true, cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [memory])
        }
        if let storeURL {
            let cloud = ModelConfiguration(schema: schema, url: storeURL,
                                           cloudKitDatabase: .private(cloudContainerIdentifier))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return container
            }
            // No iCloud, or CloudKit setup failed: a plain local store still
            // shows whatever synced before and catches up when iCloud returns.
            let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                return container
            }
        }
        startupUnavailable = true
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [memory])
    }()
}
