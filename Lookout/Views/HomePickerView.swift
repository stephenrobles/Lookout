import SwiftUI

/// Choose which HomeKit cameras and accessories the Apple TV shows. The TV
/// reads HomeKit itself; this only narrows what it displays.
struct HomePickerView: View {
    @Bindable var config: BoardConfig
    @State private var directory = HomeDirectory()

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
                                set: { config.selectedCameraIDs = $0 }
                              ))
                pickerSection(title: "Accessories", entries: directory.accessories,
                              empty: "No locks, doors, garage doors or sensors found.",
                              selection: Binding(
                                get: { config.selectedAccessoryIDs },
                                set: { config.selectedAccessoryIDs = $0 }
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
                    get: { selection.wrappedValue.isEmpty },
                    set: { all in selection.wrappedValue = all ? [] : entries.map(\.id) }
                ))
                ForEach(entries) { entry in
                    let isAll = selection.wrappedValue.isEmpty
                    let isOn = isAll || selection.wrappedValue.contains(entry.id)
                    Button {
                        guard !isAll else { return }
                        if let index = selection.wrappedValue.firstIndex(of: entry.id) {
                            selection.wrappedValue.remove(at: index)
                        } else {
                            selection.wrappedValue.append(entry.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.isCamera ? "video" : (entry.kind?.symbolName ?? "sensor"))
                                .frame(width: 24)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .foregroundStyle(.primary)
                                Text([entry.room, entry.kind?.title].compactMap { $0 }.filter { !$0.isEmpty }
                                     .joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(isAll ? .secondary : Color.accentColor)
                            }
                        }
                    }
                    .disabled(isAll)
                }
            }
        } header: {
            Text(title)
        }
    }
}
