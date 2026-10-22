import EventKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Reads EventKit on this device and writes the agenda and reminder records
/// the TV displays. Everything runs on the main actor against the shared
/// container's main context; the volume is tiny.
@Observable
final class BoardPublisher {
    static let shared = BoardPublisher()

    let eventStore = EKEventStore()
    private(set) var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    private(set) var isPublishing = false
    private(set) var lastError: String?
    private(set) var lastPublishReason: String?

    private var changeObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    /// Reminders further out than this are not published; the TV shows a
    /// handful anyway.
    private let reminderHorizonDays = 45
    private let maxPublishedReminders = 40

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.schedulePublish(after: 2) }
        }
    }

    // MARK: Access

    var hasCalendarAccess: Bool { LookoutStore.isDemo || calendarStatus == .fullAccess }
    var hasRemindersAccess: Bool { LookoutStore.isDemo || remindersStatus == .fullAccess }

    /// Stand-in calendars for demo mode, so the pickers have something to show.
    @ObservationIgnored private lazy var demoCalendars: [EKCalendar] = BoardPublisher.makeDemoCalendars(
        [("Personal", "#34C759"), ("Work", "#0A84FF"), ("Family", "#FF2D55"), ("Beard.fm", "#AF52DE")],
        type: .event, store: eventStore)
    @ObservationIgnored private lazy var demoReminderLists: [EKCalendar] = BoardPublisher.makeDemoCalendars(
        [("Errands", "#FF9F0A"), ("Home", "#0A84FF"), ("Work", "#30D158")],
        type: .reminder, store: eventStore)

    private static func makeDemoCalendars(_ items: [(String, String)], type: EKEntityType, store: EKEventStore) -> [EKCalendar] {
        items.map { title, hex in
            let calendar = EKCalendar(for: type, eventStore: store)
            calendar.title = title
            calendar.cgColor = UIColor(Color(hex: hex)).cgColor
            return calendar
        }
    }

    func requestCalendarAccess() async {
        do {
            _ = try await eventStore.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
        schedulePublish(after: 0)
    }

    func requestRemindersAccess() async {
        do {
            _ = try await eventStore.requestFullAccessToReminders()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
        schedulePublish(after: 0)
    }

    func refreshStatus() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    var calendars: [EKCalendar] {
        if LookoutStore.isDemo { return demoCalendars }
        guard hasCalendarAccess else { return [] }
        return eventStore.calendars(for: .event).sorted(by: Self.calendarOrder)
    }

    var reminderLists: [EKCalendar] {
        if LookoutStore.isDemo { return demoReminderLists }
        guard hasRemindersAccess else { return [] }
        return eventStore.calendars(for: .reminder).sorted(by: Self.calendarOrder)
    }

    nonisolated private static func calendarOrder(_ a: EKCalendar, _ b: EKCalendar) -> Bool {
        let sa = a.source?.title ?? "", sb = b.source?.title ?? ""
        if sa != sb { return sa.localizedStandardCompare(sb) == .orderedAscending }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    // MARK: Publishing

    /// Coalesces bursts of changes (EventKit fires several notifications per
    /// edit) into one publish.
    func schedulePublish(after seconds: Double) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if seconds > 0 {
                try? await Task.sleep(for: .seconds(seconds))
            }
            guard !Task.isCancelled else { return }
            await self?.publish(reason: "change")
        }
    }

    func publish(reason: String) async {
        guard !isPublishing, !LookoutStore.isDemo else { return }
        isPublishing = true
        defer { isPublishing = false }
        refreshStatus()

        let context = LookoutStore.container.mainContext
        let config = Self.dedupedConfig(in: context)

        if hasCalendarAccess {
            publishEvents(config: config, context: context)
        }
        if hasRemindersAccess {
            await publishReminders(config: config, context: context)
        }

        config.lastPublishedAt = .now
        config.publishedFromDevice = UIDevice.current.name
        config.touch()
        do {
            try context.save()
            lastError = nil
            lastPublishReason = reason
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Two devices can each create a config before CloudKit merges. Keep the
    /// newest and drop the rest so the TV never reads a stale duplicate.
    private static func dedupedConfig(in context: ModelContext) -> BoardConfig {
        let all = (try? context.fetch(FetchDescriptor<BoardConfig>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        guard let newest = all.first else {
            return BoardConfig.fetchOrCreate(in: context)
        }
        for extra in all.dropFirst() {
            context.delete(extra)
        }
        return newest
    }

    private func publishEvents(config: BoardConfig, context: ModelContext) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: max(1, config.daysAhead), to: start) ?? start

        let selected = Set(config.selectedCalendarIDs)
        let chosen = eventStore.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end,
                                                      calendars: chosen.isEmpty ? nil : chosen)
        let events = eventStore.events(matching: predicate).filter { event in
            if event.status == .canceled { return false }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                return false
            }
            return true
        }

        let existing = (try? context.fetch(FetchDescriptor<AgendaEvent>())) ?? []
        var byKey: [String: AgendaEvent] = [:]
        for record in existing {
            if byKey[record.occurrenceKey] == nil {
                byKey[record.occurrenceKey] = record
            } else {
                context.delete(record)
            }
        }

        var kept = Set<String>()
        for event in events {
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            let key = "\(identifier)|\(Int(event.startDate.timeIntervalSince1970))"
            kept.insert(key)
            let record: AgendaEvent
            if let found = byKey[key] {
                record = found
            } else {
                record = AgendaEvent()
                record.occurrenceKey = key
                context.insert(record)
                byKey[key] = record
            }
            let title = event.title ?? "Untitled"
            let location = event.location ?? ""
            let calendarTitle = event.calendar?.title ?? ""
            let hex = event.calendar?.cgColor?.lookoutHex ?? "#0A84FF"
            if record.title != title || record.startDate != event.startDate || record.endDate != event.endDate
                || record.isAllDay != event.isAllDay || record.location != location
                || record.calendarTitle != calendarTitle || record.colorHex != hex {
                record.title = title
                record.startDate = event.startDate
                record.endDate = event.endDate
                record.isAllDay = event.isAllDay
                record.location = location
                record.calendarTitle = calendarTitle
                record.colorHex = hex
                record.updatedAt = .now
            }
        }
        for (key, record) in byKey where !kept.contains(key) {
            context.delete(record)
        }
    }

    private struct ReminderRow: Sendable {
        var identifier: String
        var title: String
        var dueDate: Date?
        var hasTime: Bool
        var listTitle: String
        var colorHex: String
        var priority: Int
        var isFlagged: Bool
    }

    private func publishReminders(config: BoardConfig, context: ModelContext) async {
        let selected = Set(config.selectedReminderListIDs)
        let chosen = eventStore.calendars(for: .reminder).filter { selected.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil,
                                                                   calendars: chosen.isEmpty ? nil : chosen)
        let horizon = Calendar.current.date(byAdding: .day, value: reminderHorizonDays, to: .now) ?? .distantFuture
        let store = eventStore
        let rows: [ReminderRow] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let rows: [ReminderRow] = (reminders ?? []).compactMap { reminder in
                    guard let components = reminder.dueDateComponents,
                          let due = Calendar.current.date(from: components) else { return nil }
                    guard due <= horizon else { return nil }
                    return ReminderRow(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        dueDate: due,
                        hasTime: components.hour != nil,
                        listTitle: reminder.calendar?.title ?? "",
                        colorHex: reminder.calendar?.cgColor?.lookoutHex ?? "#FF9F0A",
                        priority: reminder.priority,
                        isFlagged: false
                    )
                }
                continuation.resume(returning: rows)
            }
        }
        let sorted = rows.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(maxPublishedReminders)

        let existing = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []
        var byID: [String: ReminderItem] = [:]
        for record in existing {
            if byID[record.reminderIdentifier] == nil {
                byID[record.reminderIdentifier] = record
            } else {
                context.delete(record)
            }
        }
        var kept = Set<String>()
        for row in sorted {
            kept.insert(row.identifier)
            let record: ReminderItem
            if let found = byID[row.identifier] {
                record = found
            } else {
                record = ReminderItem()
                record.reminderIdentifier = row.identifier
                context.insert(record)
                byID[row.identifier] = record
            }
            if record.title != row.title || record.dueDate != row.dueDate || record.hasTime != row.hasTime
                || record.listTitle != row.listTitle || record.colorHex != row.colorHex
                || record.priority != row.priority || record.isFlagged != row.isFlagged {
                record.title = row.title
                record.dueDate = row.dueDate
                record.hasTime = row.hasTime
                record.listTitle = row.listTitle
                record.colorHex = row.colorHex
                record.priority = row.priority
                record.isFlagged = row.isFlagged
                record.updatedAt = .now
            }
        }
        for (identifier, record) in byID where !kept.contains(identifier) {
            context.delete(record)
        }
    }
}
