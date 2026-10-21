import SwiftUI

/// Time, date, what's next, and any Home alert. Not a card: it sits directly
/// on the wallpaper so the clock reads as the anchor of the board.
struct ClockPanel: View {
    let events: [AgendaEvent]
    let alerts: [HomeStatusItem]
    let settings: TVSettings

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(settings.clockText(now))
                        .font(BoardTheme.clock)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let period = settings.periodText(now) {
                        Text(period)
                            .font(BoardTheme.clockPeriod)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, -6)
                .padding(.bottom, -10)

                Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(BoardTheme.date)

                Text(nextUpText(now))
                    .font(BoardTheme.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !alerts.isEmpty {
                    alertBanner
                        .padding(.top, 8)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var alertBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(alertHeadline)
                    .font(BoardTheme.rowStrong)
                Text(alerts.map { "\($0.name) \($0.stateText.lowercased())" }.joined(separator: " · "))
                    .font(BoardTheme.rowSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoardTheme.alert, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var alertHeadline: String {
        let doors = alerts.filter { $0.kind == .lock || $0.kind == .door || $0.kind == .garageDoor || $0.kind == .contactSensor }
        if doors.count == alerts.count {
            return doors.count == 1 ? "1 door needs attention" : "\(doors.count) doors need attention"
        }
        return alerts.count == 1 ? "1 accessory needs attention" : "\(alerts.count) accessories need attention"
    }

    private func nextUpText(_ now: Date) -> String {
        let calendar = Calendar.current
        let today = events.filter { calendar.isDate($0.startDate, inSameDayAs: now) && !$0.isAllDay }
        if let current = today.first(where: { $0.startDate <= now && $0.endDate > now }) {
            let minutes = Int(current.endDate.timeIntervalSince(now) / 60)
            return "Now: \(current.title) · \(Self.duration(minutes)) left"
        }
        if let next = today.first(where: { $0.startDate > now }) {
            let minutes = Int(next.startDate.timeIntervalSince(now) / 60)
            return "Next: \(next.title) in \(Self.duration(minutes))"
        }
        let allDay = events.filter { calendar.isDate($0.startDate, inSameDayAs: now) && $0.isAllDay }
        if today.isEmpty, allDay.isEmpty {
            return "Nothing scheduled today"
        }
        return "Nothing more today"
    }

    private static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
