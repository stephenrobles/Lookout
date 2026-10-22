import Foundation
import SwiftData

/// `-LookoutSchemaSeed` writes one record of every model with a value in every
/// field, so CloudKit's Development schema learns all record types and fields
/// (CloudKit only learns fields that carry values, including the asset form of
/// the wallpaper photo). Run a Debug build once with the argument on a device
/// signed in to iCloud, wait for the upload, then deploy the schema to
/// Production in CloudKit Console. The next normal publish removes the seed
/// event and reminder because their keys match nothing in the calendar.
nonisolated enum LookoutSchemaSeed {
    static var isRequested: Bool {
        CommandLine.arguments.contains("-LookoutSchemaSeed") && !LookoutStore.isDemo
    }

    @MainActor
    static func seed(into context: ModelContext) {
        let config = BoardConfig.fetchOrCreate(in: context)
        // Every optional on the config gets a value once; the photo is a 1×1
        // JPEG and is never shown because wallpaperUsesPhoto stays false.
        if config.wallpaperImageData == nil {
            config.wallpaperImageData = Data(base64Encoded:
                "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAAAP/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AKpgA//Z")
        }
        if config.lastPublishedAt == nil { config.lastPublishedAt = .now }
        if config.publishedFromDevice.isEmpty { config.publishedFromDevice = "Schema seed" }
        if config.selectedCalendarIDsRaw.isEmpty { config.selectedCalendarIDsRaw = "seed" }
        if config.selectedReminderListIDsRaw.isEmpty { config.selectedReminderListIDsRaw = "seed" }
        if config.selectedCameraIDsRaw.isEmpty { config.selectedCameraIDsRaw = "seed" }
        if config.selectedAccessoryIDsRaw.isEmpty { config.selectedAccessoryIDsRaw = "seed" }
        config.touch()

        let event = AgendaEvent()
        event.occurrenceKey = "schema-seed"
        event.title = "Schema seed"
        event.startDate = .now
        event.endDate = .now.addingTimeInterval(3600)
        event.isAllDay = false
        event.location = "Schema seed"
        event.calendarTitle = "Schema seed"
        event.colorHex = "#0A84FF"
        event.updatedAt = .now
        context.insert(event)

        let reminder = ReminderItem()
        reminder.reminderIdentifier = "schema-seed"
        reminder.title = "Schema seed"
        reminder.dueDate = .now
        reminder.hasTime = true
        reminder.listTitle = "Schema seed"
        reminder.colorHex = "#FF9F0A"
        reminder.priority = 1
        reminder.isFlagged = true
        reminder.updatedAt = .now
        context.insert(reminder)

        try? context.save()
    }

    /// Clears the seed selections so the pickers go back to "All" after the
    /// schema has been learned.
    @MainActor
    static func cleanSelections(in context: ModelContext) {
        guard let config = BoardConfig.fetchCurrent(in: context) else { return }
        for keyPath in [\BoardConfig.selectedCalendarIDsRaw, \BoardConfig.selectedReminderListIDsRaw,
                        \BoardConfig.selectedCameraIDsRaw, \BoardConfig.selectedAccessoryIDsRaw]
        where config[keyPath: keyPath] == "seed" {
            config[keyPath: keyPath] = ""
        }
        if config.publishedFromDevice == "Schema seed" { config.publishedFromDevice = "" }
        try? context.save()
    }
}
