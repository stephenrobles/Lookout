import SwiftData
import SwiftUI

/// The whole board: wallpaper, three columns, and the corner button that
/// opens the TV's own settings.
struct BoardView: View {
    @Query(sort: \BoardConfig.updatedAt, order: .reverse) private var configs: [BoardConfig]
    @Query(sort: \AgendaEvent.startDate) private var events: [AgendaEvent]
    @Query(sort: \ReminderItem.dueDate) private var reminders: [ReminderItem]

    @State private var settings = TVSettings.shared
    @State private var weather = WeatherModel()
    @State private var home = HomeMonitor()
    @State private var showSettings = false
    @State private var liveCamera: CameraEntry?

    private var snapshot: BoardSnapshot { BoardSnapshot(config: configs.first) }

    var body: some View {
        let snapshot = snapshot
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

                AgendaPanel(events: events, settings: settings, hasConfig: snapshot.hasConfig)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                let right = snapshot.rightColumn
                if !right.isEmpty {
                    VStack(spacing: BoardTheme.gutter) {
                        ForEach(right) { kind in
                            rightPanel(kind, snapshot: snapshot)
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
        .fullScreenCover(isPresented: $showSettings) {
            TVSettingsView(snapshot: snapshot)
        }
        .fullScreenCover(item: $liveCamera) { camera in
            LiveCameraView(camera: camera)
        }
    }

    @ViewBuilder
    private func rightPanel(_ kind: PanelKind, snapshot: BoardSnapshot) -> some View {
        switch kind {
        case .cameras:
            CamerasPanel(cameras: visibleCameras(snapshot), isReady: home.isReady, isDenied: home.isDenied) { camera in
                liveCamera = camera
            }
        case .home:
            HomePanel(items: visibleStatuses(snapshot), isReady: home.isReady, isDenied: home.isDenied, settings: settings)
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

    /// Keeps the phone's order. An empty selection means everything, and so
    /// does a selection that matches nothing here (for example keys saved by
    /// an older build), so the panel never goes blank.
    private static func chosen<Item: Identifiable>(_ ids: [String], from all: [Item]) -> [Item] where Item.ID == String {
        guard !ids.isEmpty else { return all }
        let picked = ids.compactMap { id in all.first { $0.id == id } }
        return picked.isEmpty ? all : picked
    }
}
