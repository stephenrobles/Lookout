import SwiftUI

/// Choose which HomeKit cameras and accessories the Apple TV shows. The TV
/// reads HomeKit itself; this only narrows what it displays.
struct HomePickerView: View {
    @Bindable var config: BoardConfig
    @State private var directory = HomeDirectory()
    @State private var publisher = BoardPublisher.shared

    var body: some View {
        List {
            if directory.isDenied {
                Section {
                    Text("HomeKit access is off. Turn it on in Settings › Privacy & Security › HomeKit to choose cameras and accessories.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            } else if directory.isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading your home…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                pickerSection(title: "Cameras", entries: directory.cameras,
                              empty: "No HomeKit cameras found.",
                              selection: Binding(
                                get: { config.selectedCameraIDs },
                                set: { config.selectedCameraIDs = $0; publisher.schedulePublish(after: 1, claim: true) }
                              ))
                pickerSection(title: "Accessories", entries: directory.accessories,
                              empty: "No lights, plugs, locks, doors, garage doors or sensors found.",
                              selection: Binding(
                                get: { config.selectedAccessoryIDs },
                                set: { config.selectedAccessoryIDs = $0; publisher.schedulePublish(after: 1, claim: true) }
                              ))
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { directory.start() }
    }

    @ViewBuilder
    private func pickerSection(title: String, entries: [HomeAccessoryEntry], empty: String,
                               selection: Binding<[String]>) -> some View {
        Section {
            if entries.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("All", isOn: Binding(
                    get: { SourceSelection.isAll(selection.wrappedValue) },
                    set: { all in selection.wrappedValue = SourceSelection.selectingAll(all) }
                ))
                ForEach(entries) { entry in
                    let isOn = SourceSelection.contains(selection.wrappedValue, entry.id)
                    Button {
                        selection.wrappedValue = SourceSelection.toggling(
                            entry.id, in: selection.wrappedValue, among: entries.map(\.id))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.isCamera ? "video" : (entry.kind?.symbolName ?? "sensor"))
                                .frame(width: 24)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .foregroundStyle(Color.primary)
                                Text([directory.hasMultipleHomes ? entry.home : nil, entry.room, entry.kind?.title]
                                     .compactMap { $0 }.filter { !$0.isEmpty }
                                     .joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
        } header: {
            Text(title)
        } footer: {
            if !entries.isEmpty {
                Text("Turn off All to show none, or tap an item to leave it out.")
            }
        }
    }
}
