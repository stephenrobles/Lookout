import SwiftUI

/// Upcoming events grouped by day, with a "now" rule through today.
struct AgendaPanel: View {
    let events: [AgendaEvent]
    let settings: TVSettings
    let hasConfig: Bool

    private struct Day: Identifiable {
        let id: Date
        let title: String
        let events: [AgendaEvent]
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            BoardCard(title: "Agenda", symbolName: "calendar") {
                HStack(spacing: 8) {
                    Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                    Text(settings.timeText(now))
                        .font(BoardTheme.label)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } content: {
                let days = groupedDays(now)
                if days.isEmpty {
                    emptyState
                } else {
                    Color.clear.overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 12) {
                                BoardLabel(text: day.title, color: Color.accentColor)
                                ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                                    if Calendar.current.isDateInToday(day.id), shouldShowNowRule(before: event, in: day.events, index: index, now: now) {
                                        nowRule(now)
                                    }
                                    EventRow(event: event, now: now, settings: settings)
                                }
                                if Calendar.current.isDateInToday(day.id), day.events.allSatisfy({ $0.isAllDay || $0.endDate <= now }), !day.events.isEmpty {
                                    nowRule(now)
                                }
                            }
                        }
                    }
                    }
                    .clipped()
                    .bottomFade()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasConfig {
                Text("Nothing coming up")
                    .font(BoardTheme.rowStrong)
                Text("Events from the calendars chosen on your iPhone will appear here.")
                    .font(BoardTheme.row)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for your iPhone")
                    .font(BoardTheme.rowStrong)
                Text("Open Lookout on your iPhone, sign in to the same iCloud account as this Apple TV, and allow calendar access. Your agenda appears here a few moments after it publishes.")
                    .font(BoardTheme.row)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nowRule(_ now: Date) -> some View {
        HStack(spacing: 10) {
            BoardLabel(text: "Now", color: Color.accentColor)
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(height: 2)
        }
        .padding(.vertical, 2)
    }

    private func shouldShowNowRule(before event: AgendaEvent, in dayEvents: [AgendaEvent], index: Int, now: Date) -> Bool {
        guard !event.isAllDay, event.startDate > now else { return false }
        // Only before the first future timed event, and only if something came before it.
        let previous = dayEvents[..<index]
        guard previous.contains(where: { !$0.isAllDay }) || previous.contains(where: { $0.isAllDay }) else {
            return !previous.isEmpty
        }
        return !previous.contains { !$0.isAllDay && $0.startDate > now }
    }

    private func groupedDays(_ now: Date) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: [AgendaEvent]] = [:]
        for event in events {
            // Multi-day all-day events already under way show under today.
            var day = calendar.startOfDay(for: event.startDate)
            if day < today, event.endDate > today { day = today }
            guard day >= today else { continue }
            if !event.isAllDay, event.endDate <= now, day == today {
                // Keep finished events today, dimmed, so the day reads as a whole.
            }
            buckets[day, default: []].append(event)
        }
        return buckets.keys.sorted().prefix(6).map { day in
            let sorted = buckets[day]!.sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.startDate < $1.startDate
            }
            return Day(id: day, title: dayTitle(day, today: today), events: sorted)
        }
    }

    private func dayTitle(_ day: Date, today: Date) -> String {
        let calendar = Calendar.current
        if day == today { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), day == tomorrow { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct EventRow: View {
    let event: AgendaEvent
    let now: Date
    let settings: TVSettings

    private var isPast: Bool { !event.isAllDay && event.endDate <= now }
    private var isCurrent: Bool { !event.isAllDay && event.startDate <= now && event.endDate > now }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(event.isAllDay ? "All day" : settings.timeText(event.startDate))
                .font(event.isAllDay ? BoardTheme.label : BoardTheme.rowStrong)
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: settings.uses24Hour ? 96 : 140, alignment: .leading)
                .padding(.top, event.isAllDay ? 5 : 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: event.colorHex))
                .frame(width: 6)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(BoardTheme.row)
                    .lineLimit(1)
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(BoardTheme.rowSecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !event.isAllDay {
                    Text("until \(settings.timeText(event.endDate))")
                        .font(BoardTheme.rowSecondary)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isPast ? 0.45 : 1)
    }
}
