import SwiftUI

/// Which optional panels appear, and the order of the right-hand column.
struct PanelsView: View {
    @Bindable var config: BoardConfig

    var body: some View {
        List {
            Section("Show") {
                ForEach(PanelKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { config.isEnabled(kind) },
                        set: { config.setEnabled(kind, $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(kind.title, systemImage: kind.symbolName)
                            Text(kind.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { config.showHomeAlerts },
                    set: { config.showHomeAlerts = $0; config.touch() }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Home alerts", systemImage: "exclamationmark.triangle")
                        Text("An orange banner under the clock when a door is unlocked, a garage is open, or a lock is jammed. Works with or without the Home panel.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(config.panelOrder) { kind in
                    HStack {
                        Label(kind.title, systemImage: kind.symbolName)
                        Spacer()
                        if !config.isEnabled(kind) {
                            Text("Off")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { source, destination in
                    var order = config.panelOrder
                    order.move(fromOffsets: source, toOffset: destination)
                    config.panelOrder = order
                }
            } header: {
                Text("Right column order")
            } footer: {
                Text("Top to bottom on the Apple TV. Weather always sits under the clock, and the agenda fills the middle.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Panels")
        .navigationBarTitleDisplayMode(.inline)
    }
}
