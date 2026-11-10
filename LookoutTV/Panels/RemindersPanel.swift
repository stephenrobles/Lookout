import SwiftUI

/// Reminders from the iPhone. Normally one list of due items, soonest
/// first, in the right column. With "Show lists separately" on it becomes a
/// strip under the agenda with up to three lists side by side, which may
/// include items without a due date.
struct RemindersPanel: View {
    let reminders: [ReminderItem]
    let limit: Int
    var sections = false
    let settings: TVSettings

    static let maxSections = 3

    private struct ListSection: Identifiable {
        let id: String
        let colorHex: String
        let items: [ReminderItem]
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            BoardCard(title: String(localized: "Reminders"), symbolName: "checklist") {
                if sections {
                    sectioned(now: now)
                } else {
                    combined(now: now)
                }
            }
        }
    }

    // MARK: One list

    @ViewBuilder
    private func combined(now: Date) -> some View {
        let items = Array(reminders.filter { $0.dueDate != nil }.sorted(by: Self.ordered).prefix(limit))
        if items.isEmpty {
            empty("No reminders due")
        } else {
            Color.clear.overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        row(item, now: now, showsList: true)
                    }
                }
            }
            .clipped()
            .bottomFade()
        }
    }

    // MARK: One section per list

    private var listSections: [ListSection] {
        let groups = Dictionary(grouping: reminders, by: \.listTitle)
        let titles = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(Self.maxSections)
        return titles.map { title in
            let items = (groups[title] ?? []).sorted(by: Self.ordered)
            return ListSection(id: title, colorHex: items.first?.colorHex ?? "#FF9F0A",
                               items: Array(items.prefix(limit)))
        }
    }

    @ViewBuilder
    private func sectioned(now: Date) -> some View {
        let lists = listSections
        if lists.isEmpty {
            empty("Nothing on your lists")
        } else {
            Color.clear.overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(lists) { list in
                        VStack(alignment: .leading, spacing: 12) {
                            BoardLabel(text: list.id.isEmpty ? String(localized: "Reminders") : list.id,
                                       color: Color(hex: list.colorHex))
                            ForEach(list.items) { item in
                                row(item, now: now, showsList: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .clipped()
            .bottomFade()
        }
    }

    // MARK: Rows

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(BoardTheme.row)
            .foregroundStyle(.secondary)
    }

    /// Dated items soonest first, then undated ones by name.
    private static func ordered(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func row(_ item: ReminderItem, now: Date, showsList: Bool) -> some View {
        let overdue = (item.dueDate ?? .distantFuture) < (item.hasTime ? now : Calendar.current.startOfDay(for: now))
        let hasPriority = item.priority > 0 && item.priority <= 4
        let hasDetail = item.dueDate != nil || hasPriority || (showsList && !item.listTitle.isEmpty)
        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .strokeBorder(Color(hex: item.colorHex), lineWidth: 3)
                .frame(width: 24, height: 24)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.title)
                    .font(BoardTheme.row)
                    .lineLimit(showsList ? 1 : 2)
                if hasDetail {
                    HStack(spacing: 8) {
                        if let due = item.dueDate {
                            Text(verbatim: dueText(due, hasTime: item.hasTime, now: now))
                                .foregroundStyle(overdue ? BoardTheme.overdue : .secondary)
                        }
                        if hasPriority {
                            Text(verbatim: String("!!!".prefix(item.priority == 1 ? 3 : 2)))
                                .foregroundStyle(BoardTheme.overdue)
                        }
                        if showsList, !item.listTitle.isEmpty {
                            Text(verbatim: "· \(item.listTitle)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(BoardTheme.rowSecondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func dueText(_ due: Date, hasTime: Bool, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) { day = String(localized: "Today") }
        else if calendar.isDateInTomorrow(due) { day = String(localized: "Tomorrow") }
        else if calendar.isDateInYesterday(due) { day = String(localized: "Yesterday") }
        else if abs(due.timeIntervalSince(now)) < 6 * 86_400 { day = due.formatted(.dateTime.weekday(.wide)) }
        else { day = due.formatted(.dateTime.month(.abbreviated).day()) }
        return hasTime ? "\(day) \(settings.timeText(due))" : day
    }
}
