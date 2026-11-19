import CloudKit
import Foundation
import Observation

/// Reads the board straight from iCloud, beside the synced store.
///
/// The store normally keeps itself current, but it is a local cache with
/// state of its own: it can be cleared by tvOS, miss the silent push that
/// tells it to download, or stop importing, and from the couch all of those
/// look the same ("Last update from iPhone: Never"). This asks iCloud for the
/// records themselves every few minutes and keeps them in memory, so the
/// board has a second, stateless source and Settings can say which side is
/// behind. `BoardView` shows whichever source is newer.
///
/// SwiftData mirrors each model into the private database's
/// `com.apple.coredata.cloudkit.zone` as a `CD_<Model>` record with one
/// `CD_<property>` field per property; that is the format read here.
@Observable
final class CloudBoardReader {
    static let shared = CloudBoardReader()

    enum State: Equatable {
        case idle
        /// iCloud answered and holds a board.
        case current
        /// iCloud answered but the iPhone has not uploaded a board.
        case empty
        case noAccount
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    /// Nil until iCloud has returned a board.
    private(set) var snapshot: BoardSnapshot?
    private(set) var events: [AgendaEvent] = []
    private(set) var reminders: [ReminderItem] = []
    private(set) var wallpaperData: Data?

    /// Set by the board when it needs the wallpaper photo from here because
    /// the synced store has none.
    var wantsWallpaper = false

    private let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone",
                                         ownerName: CKCurrentUserDefaultName)
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var token: CKServerChangeToken?
    private var configID: CKRecord.ID?
    private var wallpaperTag: String?
    private var wallpaperFetchedAt = Date.distantPast
    private var isRefreshing = false
    private var retryFull = false

    private static let pollInterval: Duration = .seconds(300)
    private static let wallpaperRefetchInterval: TimeInterval = 30 * 60

    private enum RecordType {
        static let config = "CD_BoardConfig"
        static let event = "CD_AgendaEvent"
        static let reminder = "CD_ReminderItem"
    }

    /// Every field the board reads, without the wallpaper photo: that is an
    /// asset of up to a few megabytes and is fetched on its own, when needed.
    /// Core Data moves an oversized string into a `_ckAsset` twin, which can
    /// only happen to the selection lists.
    private static let desiredKeys: [CKRecord.FieldKey] = {
        let plain = ["entityName", "id", "updatedAt",
                     "daysAhead", "enabledPanelsRaw", "panelOrderRaw", "wallpaperPresetRaw", "wallpaperUsesPhoto",
                     "wallpaperDim", "wallpaperBlur", "selectedCameraIDsRaw", "selectedAccessoryIDsRaw",
                     "selectedReminderListIDsRaw", "maxReminders", "showHomeAlerts", "lastPublishedAt",
                     "publishedFromDevice",
                     "occurrenceKey", "title", "startDate", "endDate", "isAllDay", "location", "calendarTitle",
                     "colorHex",
                     "reminderIdentifier", "dueDate", "hasTime", "listTitle", "priority", "isFlagged"]
        let oversized = ["selectedCameraIDsRaw", "selectedAccessoryIDsRaw", "selectedReminderListIDsRaw"]
        return plain.map { "CD_\($0)" } + oversized.map { "CD_\($0)_ckAsset" }
    }()

    private init() {}

    private var database: CKDatabase {
        CKContainer(identifier: LookoutStore.cloudContainerIdentifier).privateCloudDatabase
    }

    /// Checks now and then every few minutes, for as long as the board is up.
    func run() async {
        guard !LookoutStore.isDemo else { return }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// Asks iCloud what changed since the last check. `full` forgets
    /// everything read so far and starts over.
    func refresh(full: Bool = false) async {
        guard !LookoutStore.isDemo, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if full {
            token = nil
            records = [:]
            wallpaperTag = nil
        }
        do {
            let status = try await CKContainer(identifier: LookoutStore.cloudContainerIdentifier).accountStatus()
            guard status == .available else {
                state = status == .noAccount ? .noAccount : .failed(String(localized: "iCloud is not available on this Apple TV."))
                lastChecked = .now
                return
            }
            try await fetchChanges()
            rebuild()
            await fetchWallpaperIfNeeded()
            state = snapshot == nil ? .empty : .current
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // The zone appears with the iPhone's first upload.
            records = [:]
            token = nil
            rebuild()
            state = .empty
        } catch let error as CKError where error.code == .changeTokenExpired {
            // Start over on the next check, which is asked for right away.
            token = nil
            records = [:]
            state = .failed(CloudSyncMonitor.describe(error))
            retryFull = true
        } catch {
            state = .failed(CloudSyncMonitor.describe(error))
        }
        lastChecked = .now
        if retryFull {
            retryFull = false
            isRefreshing = false
            await refresh()
        }
    }

    private func fetchChanges() async throws {
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token,
                                                               desiredKeys: Self.desiredKeys)
            for (id, result) in changes.modificationResultsByID {
                if case .success(let modification) = result {
                    records[id] = modification.record
                }
            }
            for deletion in changes.deletions {
                records[deletion.recordID] = nil
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
    }

    // MARK: Decoding

    private func rebuild() {
        let all = Array(records.values)

        let configs = all.filter { $0.recordType == RecordType.config }.map { ($0, Self.snapshot(from: $0)) }
        // Same order as `BoardConfig.ranked`.
        let best = configs.max { a, b in
            if a.1.updatedAt != b.1.updatedAt { return a.1.updatedAt < b.1.updatedAt }
            return (a.1.lastPublishedAt ?? .distantPast) < (b.1.lastPublishedAt ?? .distantPast)
        }
        snapshot = best?.1
        configID = best?.0.recordID
        if best == nil || best?.1.wallpaperUsesPhoto == false {
            wallpaperData = nil
            wallpaperTag = nil
        }

        events = all.filter { $0.recordType == RecordType.event }.map { Self.event(from: $0) }
            .sorted { $0.startDate < $1.startDate }
        reminders = all.filter { $0.recordType == RecordType.reminder }.map { Self.reminder(from: $0) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private static func string(_ record: CKRecord, _ name: String) -> String? {
        if let value = record["CD_\(name)"] as? String { return value }
        if let asset = record["CD_\(name)_ckAsset"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private static func bool(_ record: CKRecord, _ name: String) -> Bool? {
        (record["CD_\(name)"] as? NSNumber)?.boolValue
    }

    private static func int(_ record: CKRecord, _ name: String) -> Int? {
        (record["CD_\(name)"] as? NSNumber)?.intValue
    }

    private static func double(_ record: CKRecord, _ name: String) -> Double? {
        (record["CD_\(name)"] as? NSNumber)?.doubleValue
    }

    private static func date(_ record: CKRecord, _ name: String) -> Date? {
        record["CD_\(name)"] as? Date
    }

    private static func uuid(_ record: CKRecord) -> UUID {
        (record["CD_id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    /// Goes through `BoardConfig`'s own accessors so the markers and
    /// defaults are read exactly as the synced store reads them. The object
    /// is never inserted anywhere.
    private static func snapshot(from record: CKRecord) -> BoardSnapshot {
        let config = BoardConfig()
        if let value = string(record, "enabledPanelsRaw") { config.enabledPanelsRaw = value }
        if let value = string(record, "panelOrderRaw") { config.panelOrderRaw = value }
        if let value = string(record, "wallpaperPresetRaw") { config.wallpaperPresetRaw = value }
        if let value = bool(record, "wallpaperUsesPhoto") { config.wallpaperUsesPhoto = value }
        if let value = double(record, "wallpaperDim") { config.wallpaperDim = value }
        if let value = double(record, "wallpaperBlur") { config.wallpaperBlur = value }
        if let value = string(record, "selectedCameraIDsRaw") { config.selectedCameraIDsRaw = value }
        if let value = string(record, "selectedAccessoryIDsRaw") { config.selectedAccessoryIDsRaw = value }
        if let value = string(record, "selectedReminderListIDsRaw") { config.selectedReminderListIDsRaw = value }
        if let value = int(record, "maxReminders") { config.maxReminders = value }
        if let value = bool(record, "showHomeAlerts") { config.showHomeAlerts = value }
        config.lastPublishedAt = date(record, "lastPublishedAt")
        if let value = string(record, "publishedFromDevice") { config.publishedFromDevice = value }
        if let value = date(record, "updatedAt") { config.updatedAt = value }
        return BoardSnapshot(config: config)
    }

    private static func event(from record: CKRecord) -> AgendaEvent {
        let event = AgendaEvent()
        event.id = uuid(record)
        event.occurrenceKey = string(record, "occurrenceKey") ?? record.recordID.recordName
        event.title = string(record, "title") ?? ""
        event.startDate = date(record, "startDate") ?? .distantPast
        event.endDate = date(record, "endDate") ?? .distantPast
        event.isAllDay = bool(record, "isAllDay") ?? false
        event.location = string(record, "location") ?? ""
        event.calendarTitle = string(record, "calendarTitle") ?? ""
        if let value = string(record, "colorHex") { event.colorHex = value }
        return event
    }

    private static func reminder(from record: CKRecord) -> ReminderItem {
        let reminder = ReminderItem()
        reminder.id = uuid(record)
        reminder.reminderIdentifier = string(record, "reminderIdentifier") ?? record.recordID.recordName
        reminder.title = string(record, "title") ?? ""
        reminder.dueDate = date(record, "dueDate")
        reminder.hasTime = bool(record, "hasTime") ?? false
        reminder.listTitle = string(record, "listTitle") ?? ""
        if let value = string(record, "colorHex") { reminder.colorHex = value }
        reminder.priority = int(record, "priority") ?? 0
        reminder.isFlagged = bool(record, "isFlagged") ?? false
        return reminder
    }

    // MARK: Wallpaper

    /// The photo comes from the synced store whenever that has it. Only when
    /// it does not is it downloaded here, once per version of the config
    /// record and no more often than every half hour, because the record
    /// changes with every publish while the photo almost never does.
    private func fetchWallpaperIfNeeded() async {
        guard wantsWallpaper, let configID, snapshot?.wallpaperUsesPhoto == true,
              let tag = records[configID]?.recordChangeTag else { return }
        if wallpaperData != nil {
            guard tag != wallpaperTag,
                  Date.now.timeIntervalSince(wallpaperFetchedAt) > Self.wallpaperRefetchInterval else { return }
        }
        let keys = ["CD_wallpaperImageData", "CD_wallpaperImageData_ckAsset"]
        guard let results = try? await database.records(for: [configID], desiredKeys: keys),
              case .success(let record)? = results[configID] else { return }
        if let data = record["CD_wallpaperImageData"] as? Data {
            wallpaperData = data
        } else if let asset = record["CD_wallpaperImageData_ckAsset"] as? CKAsset, let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) {
            wallpaperData = data
        } else {
            return
        }
        wallpaperTag = tag
        wallpaperFetchedAt = .now
    }

    /// The board calls this when it starts needing the photo, so it does not
    /// wait for the next poll.
    func loadWallpaper() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetchWallpaperIfNeeded()
    }
}
