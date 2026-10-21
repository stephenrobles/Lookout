import HomeKit
import SwiftUI

/// Camera stills, refreshed every few seconds. Selecting a tile opens the
/// live stream full screen.
struct CamerasPanel: View {
    let cameras: [CameraEntry]
    let isReady: Bool
    let isDenied: Bool
    let open: (CameraEntry) -> Void

    private let tileSpacing: CGFloat = 16

    var body: some View {
        BoardCard(title: "Cameras", symbolName: "video.fill") {
            if isDenied {
                message("HomeKit access is off for Lookout. Allow it in Settings › Apps › Lookout.")
            } else if !isReady {
                message("Connecting to your home…")
            } else if cameras.isEmpty {
                message("No HomeKit cameras in this home.")
            } else if cameras.count <= 2 {
                VStack(spacing: tileSpacing) {
                    ForEach(cameras) { camera in
                        tile(camera)
                    }
                }
            } else {
                let columns = [GridItem(.flexible(), spacing: tileSpacing), GridItem(.flexible(), spacing: tileSpacing)]
                LazyVGrid(columns: columns, spacing: tileSpacing) {
                    ForEach(cameras) { camera in
                        tile(camera)
                    }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.row)
            .foregroundStyle(.secondary)
    }

    private func tile(_ camera: CameraEntry) -> some View {
        Button {
            open(camera)
        } label: {
            CameraTile(camera: camera, compact: cameras.count > 2)
                .aspectRatio(16 / 9, contentMode: .fit)
        }
        .buttonStyle(CameraTileButtonStyle())
    }
}

/// Focus treatment for camera tiles: a white ring and a slight lift, kept
/// small enough that neighbouring tiles in the grid stay readable.
struct CameraTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CameraTileButtonLabel(configuration: configuration)
    }
}

private struct CameraTileButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white, lineWidth: isFocused ? 4 : 0)
            }
            .scaleEffect(isFocused ? 1.04 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// One camera still with a name caption.
private struct CameraTile: View {
    let camera: CameraEntry
    let compact: Bool
    @State private var controller: CameraSnapshotController

    init(camera: CameraEntry, compact: Bool) {
        self.camera = camera
        self.compact = compact
        _controller = State(initialValue: CameraSnapshotController(profile: camera.profile))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if camera.profile == nil {
                DemoCameraPlaceholder(name: camera.name)
            } else if let snapshot = controller.snapshot {
                CameraSourceView(source: snapshot)
            } else {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 10) {
                        Image(systemName: controller.failed ? "video.slash" : "video")
                            .font(.system(size: 34))
                        Text(controller.failed ? "No picture" : "Connecting…")
                            .font(BoardTheme.rowSecondary)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            Text(camera.name)
                .font(compact ? BoardTheme.chipState : BoardTheme.chipTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .shadow(radius: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await controller.run() }
    }
}

/// A stand-in picture for demo mode, so the layout can be judged without a home.
struct DemoCameraPlaceholder: View {
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#3B5B48"), Color(hex: "#1D2C24")],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "video.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

/// Full-screen live stream, dismissed with the Menu button.
struct LiveCameraView: View {
    let camera: CameraEntry
    @Environment(\.dismiss) private var dismiss
    @State private var controller: CameraStreamController

    init(camera: CameraEntry) {
        self.camera = camera
        _controller = State(initialValue: CameraStreamController(profile: camera.profile))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if camera.profile == nil {
                DemoCameraPlaceholder(name: camera.name)
                    .ignoresSafeArea()
            } else if let stream = controller.stream {
                CameraSourceView(source: stream)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(controller.errorText ?? "Starting stream…")
                        .font(BoardTheme.row)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 14, height: 14)
                Text(camera.name)
                    .font(BoardTheme.cardTitle)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .padding(40)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }
}
