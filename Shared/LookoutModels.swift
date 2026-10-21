import Foundation
import SwiftData

// MARK: - Panels

/// The optional panels on the board. The clock and the agenda are always
/// present; these can be switched off from the iPhone app.
nonisolated enum PanelKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case weather, cameras, home, reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: "Weather"
        case .cameras: "Cameras"
        case .home: "Home"
        case .reminders: "Reminders"
        }
    }

    var symbolName: String {
        switch self {
        case .weather: "cloud.sun"
        case .cameras: "video"
        case .home: "house"
        case .reminders: "checklist"
        }
    }

    var summary: String {
        switch self {
        case .weather: "Current conditions, the next hours and the week ahead. Location is set on the Apple TV."
        case .cameras: "Snapshots from the HomeKit cameras you choose, with a live view on selection."
        case .home: "Locks, doors, garage, sensors and temperatures from HomeKit."
        case .reminders: "Incomplete reminders with a due date from the lists you choose."
        }
    }

    /// Panels that stack in the board's right column, in a user-chosen order.
    /// Weather always sits under the clock.
    static let rightColumn: [PanelKind] = [.cameras, .home, .reminders]
}

// MARK: - Wallpaper presets

/// Built-in gradient wallpapers. Available on both devices; a photo picked on
/// the iPhone replaces them when `BoardConfig.wallpaperUsesPhoto` is on.
nonisolated enum WallpaperPreset: String, CaseIterable, Identifiable, Sendable {
    case midnight, forest, dusk, ocean, graphite, ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .forest: "Forest"
        case .dusk: "Dusk"
        case .ocean: "Ocean"
        case .graphite: "Graphite"
        case .ember: "Ember"
        }
    }

    /// Top-leading to bottom-trailing stops, as hex.
    var stops: [String] {
        switch self {
        case .midnight: ["#0B1026", "#1B2A4A", "#0E1A33"]
        case .forest: ["#0F2A1F", "#1F4D3A", "#0B1F17"]
        case .dusk: ["#2B1B3D", "#6B3A5B", "#1D1430"]
        case .ocean: ["#06283D", "#1363DF", "#0A3D62"]
        case .graphite: ["#1C1C1E", "#3A3A3C", "#161618"]
        case .ember: ["#2D1206", "#8A3B12", "#1E0C04"]
        }
    }

    static let `default`: WallpaperPreset = .midnight
}

// MARK: - BoardConfig

/// One record describing how the board looks and what it shows. Written by the
/// iPhone app, read by the Apple TV. Every property has a default and nothing
/// is unique, so the model can be mirrored through CloudKit.
@Model
final class BoardConfig {
    var id: UUID = UUID()
    /// How many days of calendar events to publish, counting today.
    var daysAhead: Int = 5
    var enabledPanelsRaw: String = "weather,cameras,home,reminders"
    var panelOrderRaw: String = "cameras,home,reminders"

    var wallpaperPresetRaw: String = WallpaperPreset.default.rawValue
    var wallpaperUsesPhoto: Bool = false
    @Attribute(.externalStorage) var wallpaperImageData: Data? = nil
    /// 0 = untouched photo, 1 = black.
    var wallpaperDim: Double = 0.35
    /// Blur radius in points, 0–40.
    var wallpaperBlur: Double = 0

    var selectedCalendarIDsRaw: String = ""
    var selectedReminderListIDsRaw: String = ""
    var selectedCameraIDsRaw: String = ""
    var selectedAccessoryIDsRaw: String = ""
    var maxReminders: Int = 6

    var lastPublishedAt: Date? = nil
    var publishedFromDevice: String = ""
    var updatedAt: Date = Date.distantPast

    init() {}
}

extension BoardConfig {
    nonisolated static func split(_ raw: String) -> [String] {
        raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    nonisolated static func join(_ values: [String]) -> String {
        values.joined(separator: ",")
    }

    var enabledPanels: Set<PanelKind> {
        get { Set(Self.split(enabledPanelsRaw).compactMap(PanelKind.init(rawValue:))) }
        set { enabledPanelsRaw = Self.join(PanelKind.allCases.filter { newValue.contains($0) }.map(\.rawValue)); touch() }
    }

    /// Right-column order, always containing every right-column panel exactly once.
    var panelOrder: [PanelKind] {
        get { Self.normalizedOrder(Self.split(panelOrderRaw).compactMap(PanelKind.init(rawValue:))) }
        set { panelOrderRaw = Self.join(Self.normalizedOrder(newValue).map(\.rawValue)); touch() }
    }

    nonisolated static func normalizedOrder(_ order: [PanelKind]) -> [PanelKind] {
        var seen: [PanelKind] = []
        for kind in order where PanelKind.rightColumn.contains(kind) && !seen.contains(kind) {
            seen.append(kind)
        }
        for kind in PanelKind.rightColumn where !seen.contains(kind) {
            seen.append(kind)
        }
        return seen
    }

    var wallpaperPreset: WallpaperPreset {
        get { WallpaperPreset(rawValue: wallpaperPresetRaw) ?? .default }
        set { wallpaperPresetRaw = newValue.rawValue; touch() }
    }

    var selectedCalendarIDs: [String] {
        get { Self.split(selectedCalendarIDsRaw) }
        set { selectedCalendarIDsRaw = Self.join(newValue); touch() }
    }

    var selectedReminderListIDs: [String] {
        get { Self.split(selectedReminderListIDsRaw) }
        set { selectedReminderListIDsRaw = Self.join(newValue); touch() }
    }

    var selectedCameraIDs: [String] {
        get { Self.split(selectedCameraIDsRaw) }
        set { selectedCameraIDsRaw = Self.join(newValue); touch() }
    }

    var selectedAccessoryIDs: [String] {
        get { Self.split(selectedAccessoryIDsRaw) }
        set { selectedAccessoryIDsRaw = Self.join(newValue); touch() }
    }

    func touch() { updatedAt = .now }

    func isEnabled(_ kind: PanelKind) -> Bool { enabledPanels.contains(kind) }

    func setEnabled(_ kind: PanelKind, _ enabled: Bool) {
        var set = enabledPanels
        if enabled { set.insert(kind) } else { set.remove(kind) }
        enabledPanels = set
    }

    /// The single config record, newest first if duplicates ever appear
    /// (two devices racing on first launch, for example).
    static func fetchCurrent(in context: ModelContext) -> BoardConfig? {
        var descriptor = FetchDescriptor<BoardConfig>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Fetches the config, creating one when the store has none. Only the
    /// iPhone app calls this; the TV never creates records.
    static func fetchOrCreate(in context: ModelContext) -> BoardConfig {
        if let existing = fetchCurrent(in: context) { return existing }
        let config = BoardConfig()
        config.updatedAt = .now
        context.insert(config)
        try? context.save()
        return config
    }
}

// MARK: - AgendaEvent

/// A flattened calendar occurrence published by the iPhone. Recurring events
/// become one record per occurrence inside the published window.
@Model
final class AgendaEvent {
    var id: UUID = UUID()
    /// `eventIdentifier` + start timestamp; stable across republishes so the
    /// TV only sees changes, not a full churn.
    var occurrenceKey: String = ""
    var title: String = ""
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast
    var isAllDay: Bool = false
    var location: String = ""
    var calendarTitle: String = ""
    var colorHex: String = "#0A84FF"
    var updatedAt: Date = Date.distantPast

    init() {}
}

// MARK: - ReminderItem

/// An incomplete reminder with a due date, published by the iPhone.
@Model
final class ReminderItem {
    var id: UUID = UUID()
    var reminderIdentifier: String = ""
    var title: String = ""
    var dueDate: Date? = nil
    var hasTime: Bool = false
    var listTitle: String = ""
    var colorHex: String = "#FF9F0A"
    /// EventKit priority: 0 none, 1 high … 9 low.
    var priority: Int = 0
    var isFlagged: Bool = false
    var updatedAt: Date = Date.distantPast

    init() {}
}

// MARK: - Board snapshot

/// A value copy of what the TV needs from `BoardConfig`, with defaults when the
/// phone has not published yet. Keeps the board views free of optionals.
nonisolated struct BoardSnapshot: Sendable {
    var enabledPanels: Set<PanelKind> = [.weather, .cameras, .home, .reminders]
    var panelOrder: [PanelKind] = PanelKind.rightColumn
    var wallpaperPreset: WallpaperPreset = .default
    var wallpaperUsesPhoto = false
    var wallpaperImageData: Data? = nil
    var wallpaperDim = 0.35
    var wallpaperBlur = 0.0
    var selectedCameraIDs: [String] = []
    var selectedAccessoryIDs: [String] = []
    var maxReminders = 6
    var lastPublishedAt: Date? = nil
    var publishedFromDevice = ""
    var hasConfig = false

    init() {}

    @MainActor
    init(config: BoardConfig?) {
        guard let config else { return }
        hasConfig = true
        enabledPanels = config.enabledPanels
        panelOrder = config.panelOrder
        wallpaperPreset = config.wallpaperPreset
        wallpaperUsesPhoto = config.wallpaperUsesPhoto
        wallpaperImageData = config.wallpaperImageData
        wallpaperDim = config.wallpaperDim
        wallpaperBlur = config.wallpaperBlur
        selectedCameraIDs = config.selectedCameraIDs
        selectedAccessoryIDs = config.selectedAccessoryIDs
        maxReminders = config.maxReminders
        lastPublishedAt = config.lastPublishedAt
        publishedFromDevice = config.publishedFromDevice
    }

    func isEnabled(_ kind: PanelKind) -> Bool { enabledPanels.contains(kind) }

    /// Enabled right-column panels in display order.
    var rightColumn: [PanelKind] { panelOrder.filter { enabledPanels.contains($0) } }
}
