import HomeKit
import SwiftUI
import UIKit

/// Wraps HomeKit's camera view so SwiftUI can show a snapshot or a stream.
struct CameraSourceView: UIViewRepresentable {
    let source: HMCameraSource?

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView()
        view.cameraSource = source
        return view
    }

    func updateUIView(_ uiView: HMCameraView, context: Context) {
        if uiView.cameraSource !== source {
            uiView.cameraSource = source
        }
    }
}

/// Takes a fresh still from a camera every few seconds. Tiles use this; the
/// Home app does the same, and it avoids holding several live streams open.
@Observable
final class CameraSnapshotController: NSObject, HMCameraSnapshotControlDelegate {
    private(set) var snapshot: HMCameraSnapshot?
    private(set) var failed = false
    private let control: HMCameraSnapshotControl?

    init(profile: HMCameraProfile?) {
        control = profile?.snapshotControl
        super.init()
        control?.delegate = self
        snapshot = control?.mostRecentSnapshot
    }

    /// Runs until cancelled.
    func run(interval: Duration = .seconds(10)) async {
        guard let control else { return }
        while !Task.isCancelled {
            control.takeSnapshot()
            try? await Task.sleep(for: interval)
        }
    }

    func cameraSnapshotControl(_ cameraSnapshotControl: HMCameraSnapshotControl,
                               didTake snapshot: HMCameraSnapshot?, error: (any Error)?) {
        if let snapshot {
            self.snapshot = snapshot
            failed = false
        } else {
            failed = true
        }
    }
}

/// Starts a live stream for the full-screen camera view and stops it when
/// the view goes away.
@Observable
final class CameraStreamController: NSObject, HMCameraStreamControlDelegate {
    private(set) var stream: HMCameraStream?
    private(set) var errorText: String?
    private let control: HMCameraStreamControl?

    init(profile: HMCameraProfile?) {
        control = profile?.streamControl
        super.init()
        control?.delegate = self
    }

    func start() {
        errorText = nil
        control?.startStream()
    }

    func stop() {
        control?.stopStream()
        stream = nil
    }

    func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) {
        stream = cameraStreamControl.cameraStream
    }

    func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl, didStopStreamWithError error: (any Error)?) {
        stream = nil
        errorText = error?.localizedDescription
    }
}
