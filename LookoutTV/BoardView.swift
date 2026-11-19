import SwiftData
import SwiftUI

/// Where the board on screen came from.
enum BoardSource: Equatable {
    /// The synced store, which is the normal case.
    case store
    /// Read straight from iCloud because the store is empty or behind.
    case direct
    /// Neither has answered yet; the layout is the last one this TV showed.
    case remembered
    case none
}

/// Everything one render of the board needs, from a single source.
private struct Board {
    var snapshot = BoardSnapshot()
    var events: [AgendaEvent] = []
    var reminders: [ReminderItem] = []
    var source = BoardSource.none
}

/// The last board this Apple TV showed, without the photo. Used while the
/// store is empty or downloading again, so the screen keeps the chosen
/// panels and cameras instead of falling back to every camera in the home.
private enum RememberedBoard {
    private static let key = "rememberedBoard"

    static func load() -> BoardSnapshot? {
        guard !LookoutStore.isDemo, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BoardSnapshot.self, from: data)
    }

    static func save(_ snapshot: BoardSnapshot) {
        guard !LookoutStore.isDemo, snapshot.hasConfig, let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// The whole board: wallpaper, three columns, and the corner button that
/// opens the TV's own settings.
struct BoardView: View {
    @Query private var configs: [BoardConfig]
    @Query(sort: \AgendaEvent.startDate) private var storedEvents: [AgendaEvent]
    @Query(sort: \ReminderItem.dueDate) private var storedReminders: [ReminderItem]
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = TVSettings.shared
    @State private var weather = WeatherModel()
    @State private var home = HomeMonitor()
    @State private var showSettings = false
    @State private var liveCamera: CameraEntry?
    @State private var reader = CloudBoardReader.shared
    @State private var remembered = RememberedBoard.load()

    /// How much newer iCloud has to be before the board switches to the
    /// direct read. Both sources learn of a publish within seconds of each
    /// other; this keeps the board on the store through that race.
    private static let directLead: TimeInterval = 5
    /// How long the store may stay behind iCloud before it is thrown away
    /// at the next launch. Longer than one poll, so a slow import passes.
    private static let storeGrace: Duration = .seconds(360)

    private var storeSnapshot: BoardSnapshot {
        BoardSnapshot(config: BoardConfig.ranked(configs).first)
    }

    private var board: Board {
        let store = storeSnapshot
        if var direct = reader.snapshot,
           !store.hasConfig || direct.freshness > store.freshness.addingTimeInterval(Self.directLead) {
            direct.wallpaperImageData = store.wallpaperImageData ?? reader.wallpaperData
            return Board(snapshot: direct, events: reader.events, reminders: reader.reminders, source: .direct)
        }
        if store.hasConfig {
            return Board(snapshot: store, events: storedEvents, reminders: storedReminders, source: .store)
        }
        // Once iCloud itself says there is no board, the remembered one is
        // history: show the setup hint instead.
        if var remembered, reader.state != .empty {
            remembered.wallpaperImageData = reader.wallpaperData
            return Board(snapshot: remembered, events: storedEvents, reminders: storedReminders, source: .remembered)
        }
        return Board(events: storedEvents, reminders: storedReminders)
    }

    var body: some View {
        let board = board
        let snapshot = board.snapshot
        let events = board.events
        let reminders = board.reminders
        ZStack {
            BoardWallpaper(snapshot: snapshot, override: settings.wallpaperOverride)

            HStack(alignment: .top, spacing: BoardTheme.gutter) {
                VStack(alignment: .leading, spacing: BoardTheme.gutter) {
                    ClockPanel(events: events,
                               alerts: snapshot.showHomeAlerts ? visibleStatuses(snapshot).filter(\.isAlert) : [],
                               settings: settings)
                    if snapshot.isEnabled(.weather) {
                        WeatherPanel(weather: weather, settings: settings) { showSettings = true }
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: BoardTheme.leftWidth)

                VStack(spacing: BoardTheme.gutter) {
                    AgendaPanel(events: events, settings: settings, hasConfig: snapshot.hasConfig)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if snapshot.showsReminderStrip {
                        RemindersPanel(reminders: reminders, limit: snapshot.maxReminders,
                                       sections: true, settings: settings)
                            .frame(height: 340)
                    }
                }

                let right = snapshot.rightColumn
                if !right.isEmpty {
                    VStack(spacing: BoardTheme.gutter) {
                        ForEach(right) { kind in
                            rightPanel(kind, snapshot: snapshot, reminders: reminders)
                        }
                    }
                    .frame(width: BoardTheme.rightWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(GlassIconButtonStyle())
            .offset(x: 22, y: -22)
        }
        .task(id: settings.locationKey) {
            await weather.run(latitude: settings.latitude, longitude: settings.longitude)
        }
        .onAppear {
            let args = CommandLine.arguments
            if LookoutStore.isDemo {
                if let i = args.firstIndex(of: "-LookoutWallpaper"), i + 1 < args.count {
                    settings.wallpaperChoice = args[i + 1]
                }
                if let i = args.firstIndex(of: "-LookoutScreen"), i + 1 < args.count, args[i + 1] == "settings" {
                    showSettings = true
                }
            }
        }
        .task {
            home.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                home.refreshValues()
            }
        }
        .task { await reader.run() }
        .onChange(of: scenePhase) { _, phase in
            // Back from sleep or the screen saver: do not wait for the next poll.
            if phase == .active { Task { await reader.refresh() } }
        }
        .task(id: snapshot.withoutPhoto) {
            if board.source == .store || board.source == .direct {
                RememberedBoard.save(snapshot)
                remembered = snapshot.withoutPhoto
            }
        }
        .task(id: snapshot.wallpaperUsesPhoto && storeSnapshot.wallpaperImageData == nil) {
            let needed = snapshot.wallpaperUsesPhoto && storeSnapshot.wallpaperImageData == nil
            reader.wantsWallpaper = needed
            if needed { await reader.loadWallpaper() }
        }
        .task(id: board.source) {
            // iCloud holds a newer board than the store and the store is not
            // catching up: it missed its push or stopped importing. The board
            // is already showing the direct read; give the store a clean
            // start next time.
            guard board.source == .direct else { return }
            try? await Task.sleep(for: Self.storeGrace)
            guard !Task.isCancelled else { return }
            LookoutStore.requestResetOnNextLaunch()
        }
        .fullScreenCover(isPresented: $showSettings) {
            TVSettingsView(snapshot: snapshot, source: board.source)
        }
        .fullScreenCover(item: $liveCamera) { camera in
            LiveCameraView(camera: camera)
        }
    }

    @ViewBuilder
    private func rightPanel(_ kind: PanelKind, snapshot: BoardSnapshot, reminders: [ReminderItem]) -> some View {
        switch kind {
        case .cameras:
            CamerasPanel(cameras: visibleCameras(snapshot), isReady: home.isReady, isDenied: home.isDenied,
                         noneChosen: SourceSelection.isNone(snapshot.selectedCameraIDs)) { camera in
                liveCamera = camera
            }
        case .home:
            HomePanel(items: visibleStatuses(snapshot), isReady: home.isReady, isDenied: home.isDenied,
                      noneChosen: SourceSelection.isNone(snapshot.selectedAccessoryIDs), settings: settings)
                .frame(maxHeight: .infinity, alignment: .top)
        case .reminders:
            RemindersPanel(reminders: reminders, limit: snapshot.maxReminders, settings: settings)
                .frame(maxHeight: .infinity, alignment: .top)
        case .weather:
            EmptyView()
        }
    }

    private func visibleCameras(_ snapshot: BoardSnapshot) -> [CameraEntry] {
        Array(Self.chosen(snapshot.selectedCameraIDs, from: home.cameras).prefix(4))
    }

    private func visibleStatuses(_ snapshot: BoardSnapshot) -> [HomeStatusItem] {
        Self.chosen(snapshot.selectedAccessoryIDs, from: home.statuses)
    }

    /// Keeps the phone's order. An empty selection means everything and the
    /// "none" marker means nothing. A chosen item that is not here right now
    /// (HomeKit still loading, a camera offline or renamed) is simply
    /// missing: it must not bring back the cameras nobody chose. Only keys
    /// from before 1.1, which were per-device identifiers and can never
    /// match, still fall back to everything.
    private static func chosen<Item: Identifiable>(_ ids: [String], from all: [Item]) -> [Item] where Item.ID == String {
        guard let wanted = SourceSelection.chosenIDs(ids) else { return all }
        guard !wanted.isEmpty else { return [] }
        let picked = wanted.compactMap { id in all.first { $0.id == id } }
        let legacy = wanted.allSatisfy { !$0.contains("|") }
        return picked.isEmpty && legacy ? all : picked
    }
}
