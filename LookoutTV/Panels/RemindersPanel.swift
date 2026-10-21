import SwiftUI

/// Due reminders, soonest first. Overdue items are called out in red.
struct RemindersPanel: View {
    let reminders: [ReminderItem]
    let limit: Int
    let settings: TVSettings

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            BoardCard(title: "Reminders", symbolName: "checklist") {
                let items = Array(reminders.prefix(limit))
                if items.isEmpty {
                    Text("No reminders due")
                        .font(BoardTheme.row)
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear.overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(items) { item in
                                row(item, now: now)
                            }
                        }
                    }
                    .clipped()
                    .bottomFade()
                }
            }
        }
    }

    private func row(_ item: ReminderItem, now: Date) -> some View {
        let overdue = (item.dueDate ?? .distantFuture) < (item.hasTime ? now : Calendar.current.startOfDay(for: now))
        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .strokeBorder(Color(hex: item.colorHex), lineWidth: 3)
                .frame(width: 24, height: 24)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(BoardTheme.row)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let due = item.dueDate {
                        Text(dueText(due, hasTime: item.hasTime, now: now))
                            .foregroundStyle(overdue ? BoardTheme.overdue : .secondary)
                    }
                    if item.priority > 0 && item.priority <= 4 {
                        Text("!!!".prefix(item.priority == 1 ? 3 : item.priority <= 4 ? 2 : 1))
                            .foregroundStyle(BoardTheme.overdue)
                    }
                    if !item.listTitle.isEmpty {
                        Text("· \(item.listTitle)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(BoardTheme.rowSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func dueText(_ due: Date, hasTime: Bool, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) { day = "Today" }
        else if calendar.isDateInTomorrow(due) { day = "Tomorrow" }
        else if calendar.isDateInYesterday(due) { day = "Yesterday" }
        else if abs(due.timeIntervalSince(now)) < 6 * 86_400 { day = due.formatted(.dateTime.weekday(.wide)) }
        else { day = due.formatted(.dateTime.month(.abbreviated).day()) }
        return hasTime ? "\(day) \(settings.timeText(due))" : day
    }
}
