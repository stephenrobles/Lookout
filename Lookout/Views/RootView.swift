import CloudKit
import SwiftData
import SwiftUI

/// The companion app's single screen: what the board shows, and how.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BoardConfig.updatedAt, order: .reverse) private var configs: [BoardConfig]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            if let config = configs.first {
                SettingsList(config: config)
                    .navigationDestination(for: StagedScreen.self) { screen in
                        switch screen {
                        case .panels: PanelsView(config: config)
                        case .wallpaper: WallpaperView(config: config)
                        case .home: HomePickerView(config: config)
                        case .calendars: CalendarPickerView(config: config)
                        }
                    }
                    .onAppear {
                        if let staged = StagedScreen.fromLaunchArguments, path.isEmpty {
                            path.append(staged)
                        }
                    }
            } else {
                ProgressView()
                    .task { _ = BoardConfig.fetchOrCreate(in: context) }
            }
        }
    }
}

/// `-LookoutScreen panels|wallpaper|home|calendars` opens a screen at launch.
/// Used to stage App Store screenshots headlessly in demo mode.
enum StagedScreen: String, Hashable {
    case panels, wallpaper, home, calendars

    static var fromLaunchArguments: StagedScreen? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-LookoutScreen"), index + 1 < args.count else { return nil }
        return StagedScreen(rawValue: args[index + 1])
    }
}

private struct SettingsList: View {
    @Bindable var config: BoardConfig
    @State private var publisher = BoardPublisher.shared
    @State private var accountStatus: CKAccountStatus?

    var body: some View {
        List {
            statusSection
            calendarSection
            remindersSection
            panelsSection
            wallpaperSection
            homeSection
            aboutSection
        }
        .navigationTitle("Lookout")
        .task { await loadAccountStatus() }
        .onChange(of: config.daysAhead) { config.touch(); publisher.schedulePublish(after: 1, claim: true) }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "appletv.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple TV board")
                            .font(.headline)
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = publisher.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let other = otherPublisher {
                    Label("\(other) publishes the calendars and reminders. Change something here or tap Publish now to publish from this \(UIDevice.current.model) instead.",
                          systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button {
                Task { await publisher.publish(reason: "manual", claim: true) }
            } label: {
                HStack {
                    Label("Publish now", systemImage: "arrow.up.circle")
                    Spacer()
                    if publisher.isPublishing {
                        ProgressView()
                    }
                }
            }
            .disabled(publisher.isPublishing || LookoutStore.isDemo)
        } footer: {
            Text("Lookout publishes automatically when your calendars or reminders change, when you open the app, and periodically in the background. With more than one iPhone or iPad on the account, the one you last changed settings on does the publishing. Open Lookout on your Apple TV signed in to the same iCloud account.")
        }
    }

    /// The device that owns publishing, when it is another one.
    private var otherPublisher: String? {
        let owner = config.publishedFromDevice
        guard !LookoutStore.isDemo, !owner.isEmpty,
              owner != BoardPublisher.deviceName, owner != UIDevice.current.name else { return nil }
        return owner
    }

    private var statusLine: String {
        if LookoutStore.isDemo { return "Demo data (not synced)" }
        switch accountStatus {
        case .available?:
            if let date = config.lastPublishedAt {
                let when = date.formatted(.relative(presentation: .named))
                if let other = otherPublisher { return "Published \(when) by \(other)" }
                return "Published \(when)"
            }
            return "iCloud ready · not published yet"
        case .noAccount?: return "Sign in to iCloud in Settings to sync"
        case .restricted?: return "iCloud is restricted on this device"
        case .couldNotDetermine?, .temporarilyUnavailable?: return "Checking iCloud…"
        case nil: return "Checking iCloud…"
        @unknown default: return "iCloud status unknown"
        }
    }

    private func loadAccountStatus() async {
        guard !LookoutStore.isDemo else { return }
        accountStatus = try? await CKContainer(identifier: LookoutStore.cloudContainerIdentifier).accountStatus()
    }

    // MARK: Calendar

    private var calendarSection: some View {
        Section("Calendar") {
            if publisher.hasCalendarAccess {
                NavigationLink {
                    CalendarPickerView(config: config)
                } label: {
                    LabeledContent("Calendars", value: calendarSummary)
                }
                Stepper(value: $config.daysAhead, in: 2...14) {
                    LabeledContent("Days shown", value: "\(config.daysAhead)")
                }
            } else {
                accessRow(title: "Allow calendar access",
                          detail: "Needed to show upcoming events on the board.",
                          status: publisher.calendarStatus) {
                    Task { await publisher.requestCalendarAccess() }
                }
            }
        }
    }

    private var calendarSummary: String {
        Self.summary(config.selectedCalendarIDs, of: publisher.calendars.count)
    }

    /// "All", "None" or "2 of 5".
    private static func summary(_ selection: [String], of total: Int) -> String {
        if SourceSelection.isAll(selection) { return "All" }
        if SourceSelection.isNone(selection) { return "None" }
        return "\(selection.count) of \(total)"
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section("Reminders") {
            if publisher.hasRemindersAccess {
                NavigationLink {
                    ReminderListPickerView(config: config)
                } label: {
                    LabeledContent("Lists", value: reminderSummary)
                }
                Stepper(value: Binding(
                    get: { config.maxReminders },
                    set: { config.maxReminders = $0; config.touch(); publisher.schedulePublish(after: 1, claim: true) }
                ), in: 3...12) {
                    LabeledContent("Items on board", value: "\(config.maxReminders)")
                }
            } else {
                accessRow(title: "Allow reminders access",
                          detail: "Needed to show due reminders on the board.",
                          status: publisher.remindersStatus) {
                    Task { await publisher.requestRemindersAccess() }
                }
            }
        }
    }

    private var reminderSummary: String {
        Self.summary(config.selectedReminderListIDs, of: publisher.reminderLists.count)
    }

    @ViewBuilder
    private func accessRow(title: String, detail: String, status: EKAuthorizationStatusProxy,
                           action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if status.isDenied {
                Text("Access is off")
                    .font(.headline)
                Text("Turn it on in Settings › Privacy & Security to show this on the board.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.subheadline)
                }
            } else {
                Button(title, action: action)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Panels

    private var panelsSection: some View {
        Section {
            NavigationLink {
                PanelsView(config: config)
            } label: {
                LabeledContent("Panels", value: panelSummary)
            }
        } header: {
            Text("Layout")
        } footer: {
            Text("The clock and the agenda are always shown.")
        }
    }

    private var panelSummary: String {
        let on = PanelKind.allCases.filter { config.isEnabled($0) }
        if on.count == PanelKind.allCases.count { return "All" }
        if on.isEmpty { return "None" }
        return on.map(\.title).joined(separator: ", ")
    }

    // MARK: Wallpaper

    private var wallpaperSection: some View {
        Section("Wallpaper") {
            NavigationLink {
                WallpaperView(config: config)
            } label: {
                HStack(spacing: 12) {
                    WallpaperThumbnail(config: config)
                        .frame(width: 64, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(config.wallpaperUsesPhoto && config.wallpaperImageData != nil
                         ? "Photo" : config.wallpaperPreset.title)
                }
            }
        }
    }

    // MARK: Home

    private var homeSection: some View {
        Section {
            NavigationLink {
                HomePickerView(config: config)
            } label: {
                LabeledContent("Cameras and accessories", value: homeSummary)
            }
        } header: {
            Text("Home")
        } footer: {
            Text("The Apple TV reads HomeKit directly. Choose here which cameras and accessories it shows.")
        }
    }

    private var homeSummary: String {
        let cameras = config.selectedCameraIDs
        let accessories = config.selectedAccessoryIDs
        if SourceSelection.isAll(cameras) && SourceSelection.isAll(accessories) { return "All" }
        if SourceSelection.isNone(cameras) && SourceSelection.isNone(accessories) { return "None" }
        return "\(Self.count(cameras)) cameras · \(Self.count(accessories)) accessories"
    }

    private static func count(_ selection: [String]) -> String {
        if SourceSelection.isAll(selection) { return "All" }
        if SourceSelection.isNone(selection) { return "No" }
        return "\(selection.count)"
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        }
    }
}

/// Keeps EventKit's enum out of the view signature.
import EventKit
typealias EKAuthorizationStatusProxy = EKAuthorizationStatus

extension EKAuthorizationStatus {
    var isDenied: Bool {
        switch self {
        case .denied, .restricted: true
        default: false
        }
    }
}

/// A small preview of the current wallpaper, used in the settings list.
struct WallpaperThumbnail: View {
    let config: BoardConfig

    var body: some View {
        ZStack {
            if config.wallpaperUsesPhoto, let data = config.wallpaperImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: config.wallpaperPreset.stops.map { Color(hex: $0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Color.black.opacity(config.wallpaperDim)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(LookoutStore.container)
}
