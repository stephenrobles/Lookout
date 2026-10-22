import EventKit
import SwiftUI

/// Choose which calendars feed the agenda. No selection means every calendar.
struct CalendarPickerView: View {
    @Bindable var config: BoardConfig
    @State private var publisher = BoardPublisher.shared

    var body: some View {
        SourcePickerList(
            title: "Calendars",
            calendars: publisher.calendars,
            selection: Binding(
                get: { config.selectedCalendarIDs },
                set: { config.selectedCalendarIDs = $0; publisher.schedulePublish(after: 1) }
            )
        )
    }
}

/// Choose which reminder lists feed the reminders panel.
struct ReminderListPickerView: View {
    @Bindable var config: BoardConfig
    @State private var publisher = BoardPublisher.shared

    var body: some View {
        SourcePickerList(
            title: "Reminder lists",
            calendars: publisher.reminderLists,
            selection: Binding(
                get: { config.selectedReminderListIDs },
                set: { config.selectedReminderListIDs = $0; publisher.schedulePublish(after: 1) }
            )
        )
    }
}

private struct SourcePickerList: View {
    let title: String
    let calendars: [EKCalendar]
    @Binding var selection: [String]

    private var grouped: [(source: String, calendars: [EKCalendar])] {
        let groups = Dictionary(grouping: calendars) { $0.source?.title ?? "Other" }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { (source: $0, calendars: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Toggle("All", isOn: Binding(
                    get: { selection.isEmpty },
                    set: { all in
                        selection = all ? [] : calendars.map(\.calendarIdentifier)
                    }
                ))
            } footer: {
                Text("Turn off All to pick specific ones.")
            }
            ForEach(grouped, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        row(for: calendar)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for calendar: EKCalendar) -> some View {
        let isAll = selection.isEmpty
        let isOn = isAll || selection.contains(calendar.calendarIdentifier)
        let title = calendar.title.trimmingCharacters(in: .whitespaces)
        return Button {
            guard !isAll else { return }
            if let index = selection.firstIndex(of: calendar.calendarIdentifier) {
                selection.remove(at: index)
            } else {
                selection.append(calendar.calendarIdentifier)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: calendar.cgColor?.lookoutHex ?? "#0A84FF"))
                    .frame(width: 12, height: 12)
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(isAll ? Color.secondary : Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
