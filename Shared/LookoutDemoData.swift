import Foundation
import SwiftData

/// Sample content for the `-LookoutDemo` launch argument. Seeds only the
/// in-memory demo container, never a synced store.
nonisolated enum LookoutDemoData {
    @MainActor
    static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
        }

        let config = BoardConfig()
        config.wallpaperPreset = .forest
        config.lastPublishedAt = .now.addingTimeInterval(-180)
        config.publishedFromDevice = "Stephen's iPhone"
        config.updatedAt = .now
        context.insert(config)

        struct Sample { let title: String; let start: Date; let end: Date; let allDay: Bool; let location: String; let cal: String; let hex: String }
        let samples: [Sample] = [
            Sample(title: "Jim on Vacation", start: today, end: at(1, 0), allDay: true, location: "", cal: "Work", hex: "#34C759"),
            Sample(title: "Intentional AI Release", start: today, end: at(1, 0), allDay: true, location: "", cal: "Beard.fm", hex: "#FF9500"),
            Sample(title: "Pilates – Reformer Flow 1", start: at(0, 16), end: at(0, 16, 50), allDay: false, location: "Club Pilates Foothill Ranch", cal: "Personal", hex: "#34C759"),
            Sample(title: "Lunch with Jim", start: at(1, 11), end: at(1, 12, 30), allDay: false, location: "Din Tai Fung", cal: "Personal", hex: "#FF9500"),
            Sample(title: "Pilates – Reformer Flow 1", start: at(1, 17, 30), end: at(1, 18, 20), allDay: false, location: "Club Pilates Foothill Ranch", cal: "Personal", hex: "#34C759"),
            Sample(title: "Podcast recording", start: at(2, 10), end: at(2, 11, 30), allDay: false, location: "Studio", cal: "Beard.fm", hex: "#AF52DE"),
            Sample(title: "Lisa's Birthday at Disneyland", start: at(4, 11), end: at(4, 20), allDay: false, location: "Disneyland Park", cal: "Family", hex: "#FF2D55"),
        ]
        for (index, sample) in samples.enumerated() {
            let event = AgendaEvent()
            event.occurrenceKey = "demo-\(index)"
            event.title = sample.title
            event.startDate = sample.start
            event.endDate = sample.end
            event.isAllDay = sample.allDay
            event.location = sample.location
            event.calendarTitle = sample.cal
            event.colorHex = sample.hex
            event.updatedAt = .now
            context.insert(event)
        }

        let reminders: [(String, Date?, Bool, String, String, Int)] = [
            ("Return library books", at(0, 17), true, "Errands", "#FF9F0A", 1),
            ("Order filters for the fridge", today, false, "Home", "#0A84FF", 0),
            ("Send invoice to Circle", at(1, 9), true, "Work", "#30D158", 5),
            ("Book dentist", at(2, 0), false, "Personal", "#BF5AF2", 0),
        ]
        for (index, item) in reminders.enumerated() {
            let reminder = ReminderItem()
            reminder.reminderIdentifier = "demo-reminder-\(index)"
            reminder.title = item.0
            reminder.dueDate = item.1
            reminder.hasTime = item.2
            reminder.listTitle = item.3
            reminder.colorHex = item.4
            reminder.priority = item.5
            reminder.updatedAt = .now
            context.insert(reminder)
        }
        try? context.save()
    }
}
