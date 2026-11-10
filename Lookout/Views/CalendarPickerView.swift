import EventKit
import SwiftUI

/// Choose which calendars feed the agenda. "All" follows new calendars as
/// they appear; turning it off and leaving nothing checked publishes nothing.
struct CalendarPickerView: View {
    @Bindable var config: BoardConfig
    @State private var publisher = BoardPublisher.shared

    var body: some View {
        SourcePickerList(
            title: "Calendars",
            calendars: publisher.calendars,
            selection: Binding(
                get: { config.selectedCalendarIDs },
                set: { config.selectedCalendarIDs = $0; publisher.schedulePublish(after: 1, claim: true) }
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
                set: { config.selectedReminderListIDs = $0; publisher.schedulePublish(after: 1, claim: true) }
            )
        )
    }
}

private struct SourcePickerList: View {
    let title: LocalizedStringKey
    let calendars: [EKCalendar]
    @Binding var selection: [String]

    private var grouped: [(source: String, calendars: [EKCalendar])] {
        let groups = Dictionary(grouping: calendars) { $0.source?.title ?? String(localized: "Other") }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { (source: $0, calendars: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Toggle("All", isOn: Binding(
                    get: { SourceSelection.isAll(selection) },
                    set: { all in selection = SourceSelection.selectingAll(all) }
                ))
            } footer: {
                Text("Turn off All to show none, or tap one to leave it out. Lookout publishes from whichever iPhone or iPad you last changed this on.")
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
        let isOn = SourceSelection.contains(selection, calendar.calendarIdentifier)
        let title = calendar.title.trimmingCharacters(in: .whitespaces)
        return Button {
            selection = SourceSelection.toggling(calendar.calendarIdentifier, in: selection,
                                                 among: calendars.map(\.calendarIdentifier))
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: calendar.cgColor?.lookoutHex ?? "#0A84FF"))
                    .frame(width: 12, height: 12)
                Text(title.isEmpty ? String(localized: "Untitled") : title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
