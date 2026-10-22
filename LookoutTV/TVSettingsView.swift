import CloudKit
import CoreLocation
import SwiftUI

/// The Apple TV's own settings: weather location, units, clock and wallpaper.
/// Content choices stay on the iPhone.
struct TVSettingsView: View {
    let snapshot: BoardSnapshot
    @State private var settings = TVSettings.shared
    @State private var accountStatus: CKAccountStatus?

    var body: some View {
        ZStack {
            // A presented view on tvOS has no backdrop of its own; without this the board shows through.
            Color(white: 0.06).ignoresSafeArea()
            settingsStack
        }
    }

    private var settingsStack: some View {
        NavigationStack {
            List {
                Section("Weather") {
                    NavigationLink {
                        LocationSearchView(settings: settings)
                    } label: {
                        LabeledContent("Location", value: settings.hasLocation ? settings.locationName : "Not set")
                    }
                    Picker("Temperature", selection: $settings.temperature) {
                        ForEach(TVSettings.TemperatureChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Clock") {
                    Picker("Time format", selection: $settings.clock) {
                        ForEach(TVSettings.ClockChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Picker("Wallpaper", selection: $settings.wallpaperChoice) {
                        Text("Follow iPhone").tag(TVSettings.followPhoneWallpaper)
                        ForEach(WallpaperPreset.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Wallpaper")
                } footer: {
                    Text("Follow iPhone shows the photo or gradient chosen in the Lookout app on your iPhone.")
                }
                Section {
                    LabeledContent("iCloud", value: accountText)
                    LabeledContent("Last update from iPhone", value: lastPublished)
                    if !snapshot.publishedFromDevice.isEmpty {
                        LabeledContent("Published by", value: snapshot.publishedFromDevice)
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Calendars, reminders, panels and the wallpaper photo are chosen in the Lookout app on an iPhone or iPad signed in to the same iCloud account.")
                }
            }
            .navigationTitle("Lookout Settings")
        }
        .task {
            guard !LookoutStore.isDemo else { return }
            accountStatus = try? await CKContainer(identifier: LookoutStore.cloudContainerIdentifier).accountStatus()
        }
    }

    private var accountText: String {
        if LookoutStore.isDemo { return "Demo" }
        switch accountStatus {
        case .available?: return "Signed in"
        case .noAccount?: return "Not signed in"
        case .restricted?: return "Restricted"
        case nil, .couldNotDetermine?, .temporarilyUnavailable?: return "Checking…"
        @unknown default: return "Unknown"
        }
    }

    private var lastPublished: String {
        guard let date = snapshot.lastPublishedAt else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }
}

/// Type a city, or use the Apple TV's own location.
struct LocationSearchView: View {
    let settings: TVSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CLPlacemark] = []
    @State private var isSearching = false
    @State private var finder = TVLocationFinder()
    @State private var searchError: String?

    var body: some View {
        List {
            Section {
                TextField("City or place", text: $query)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await useDeviceLocation() }
                } label: {
                    HStack {
                        Label("Use this Apple TV's location", systemImage: "location.fill")
                        Spacer()
                        if finder.isLocating { ProgressView() }
                    }
                }
                if let error = finder.errorText ?? searchError {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }
            if isSearching {
                Section { ProgressView() }
            } else if !results.isEmpty {
                Section("Results") {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, place in
                        Button {
                            choose(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.shortName(place))
                                Text(Self.detail(place))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Location")
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            results = try await CLGeocoder().geocodeAddressString(text)
            if results.isEmpty { searchError = "No places found." }
        } catch {
            results = []
            searchError = "Could not search right now."
        }
    }

    private func useDeviceLocation() async {
        guard let location = await finder.locate() else { return }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark.map(Self.shortName) ?? "Current location"
        settings.setLocation(name: name, latitude: location.coordinate.latitude,
                             longitude: location.coordinate.longitude)
        dismiss()
    }

    private func choose(_ place: CLPlacemark) {
        guard let location = place.location else { return }
        settings.setLocation(name: Self.shortName(place), latitude: location.coordinate.latitude,
                             longitude: location.coordinate.longitude)
        dismiss()
    }

    static func shortName(_ place: CLPlacemark) -> String {
        place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? place.name ?? "Location"
    }

    static func detail(_ place: CLPlacemark) -> String {
        [place.administrativeArea, place.country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// One-shot location lookup on the TV (approximate, by network).
@Observable
final class TVLocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private(set) var isLocating = false
    private(set) var errorText: String?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locate() async -> CLLocation? {
        guard !isLocating else { return nil }
        isLocating = true
        errorText = nil
        defer { isLocating = false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                errorText = "Location access is off for Lookout. Allow it in Settings › Privacy & Security."
                finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            errorText = "Location access is off for Lookout."
            finish(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        errorText = "Could not find this Apple TV's location."
        finish(nil)
    }
}
