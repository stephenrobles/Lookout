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

    /// How the store was opened this launch: normally, after discarding a
    /// copy that would not open, without iCloud, or not at all. The last two
    /// mean the local copy is not following iCloud; the TV says so in Settings.
    enum Mode: Sendable { case synced, rebuilt, localOnly, memory }
    nonisolated(unsafe) private(set) static var mode: Mode = .synced

    /// True when no persistent store could be opened and the app fell back to
    /// memory.
    static var startupUnavailable: Bool { mode == .memory }

    private static let resetKey = "resetStoreOnNextLaunch"

    /// Throws the local copy away at the next launch so it downloads again
    /// from iCloud. Only the Apple TV uses this: its store holds nothing that
    /// is not also in iCloud.
    static func requestResetOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
    }

    private static func removeStore(at url: URL) {
        let directory = url.deletingLastPathComponent()
        for item in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                  options: [])) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }

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
            #if os(tvOS)
            if UserDefaults.standard.bool(forKey: resetKey) {
                UserDefaults.standard.removeObject(forKey: resetKey)
                removeStore(at: storeURL)
            }
            #endif
            let cloud = ModelConfiguration(schema: schema, url: storeURL,
                                           cloudKitDatabase: .private(cloudContainerIdentifier))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return container
            }
            #if os(tvOS)
            // The TV's store sits in Caches, which tvOS may clear when space
            // runs low. A store left damaged fails to open on every launch
            // from then on, so restarting never helped. Nothing in it is
            // original: discard it and download again.
            removeStore(at: storeURL)
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                mode = .rebuilt
                return container
            }
            #endif
            // No iCloud, or CloudKit setup failed: a plain local store still
            // shows whatever synced before and catches up when iCloud returns.
            let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                mode = .localOnly
                return container
            }
        }
        mode = .memory
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [memory])
    }()
}
