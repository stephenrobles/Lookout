import HomeKit
import SwiftUI
import UIKit

/// Wraps HomeKit's camera view so SwiftUI can show a snapshot or a stream.
/// `HMCameraView` stretches its picture to whatever frame it gets, so callers
/// size it with `aspectRatio` from the feed and crop or letterbox around it.
struct CameraSourceView: UIViewRepresentable {
    let source: HMCameraSource?

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView()
        view.backgroundColor = .black
        view.cameraSource = source
        return view
    }

    func updateUIView(_ uiView: HMCameraView, context: Context) {
        if uiView.cameraSource !== source {
            uiView.cameraSource = source
        }
    }
}

/// One picture per camera, shared by its tile and the full-screen view.
///
/// Tiles ask for stills every few seconds, as the Home app does. Cameras that
/// never answer a snapshot request (some third-party models only stream)
/// fall back to a live stream after a couple of failures. The full-screen
/// view always asks for the stream. Only one stream is ever open per camera,
/// and it is retried with growing delays when it drops.
@Observable
final class CameraFeed: NSObject, HMCameraSnapshotControlDelegate, HMCameraStreamControlDelegate {
    private(set) var snapshot: HMCameraSnapshot?
    private(set) var stream: HMCameraStream?
    private(set) var errorText: String?
    /// No still and no stream after trying both.
    private(set) var failed = false

    /// The latest picture, live when there is one.
    var source: HMCameraSource? { stream ?? snapshot }
    var isLive: Bool { stream != nil }

    /// Width over height of the picture; 16:9 until the camera says otherwise.
    var aspectRatio: CGFloat {
        if let ratio = source?.aspectRatio, ratio > 0 { return CGFloat(ratio) }
        return 16 / 9
    }

    static let snapshotInterval: Duration = .seconds(10)
    static let failuresBeforeStreaming = 2

    let profile: HMCameraProfile?
    private var tileViews = 0
    private var liveViews = 0
    private var snapshotFailures = 0
    private var streamWanted = false
    private var snapshotTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryDelay: Duration = .seconds(3)

    init(profile: HMCameraProfile?) {
        self.profile = profile
        super.init()
        profile?.snapshotControl?.delegate = self
        profile?.streamControl?.delegate = self
        snapshot = profile?.snapshotControl?.mostRecentSnapshot
    }

    // MARK: Attachment

    /// Keeps the feed running for as long as the calling view's task lives.
    /// `live` asks for the stream outright; otherwise stills are preferred.
    func run(live: Bool) async {
        attach(live: live)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        detach(live: live)
    }

    private func attach(live: Bool) {
        if live { liveViews += 1 } else { tileViews += 1 }
        update()
    }

    private func detach(live: Bool) {
        if live { liveViews = max(0, liveViews - 1) } else { tileViews = max(0, tileViews - 1) }
        update()
    }

    private var wantsStream: Bool {
        liveViews > 0 || (tileViews > 0 && snapshotFailures >= Self.failuresBeforeStreaming)
    }

    private func update() {
        guard profile != nil else { return }
        if tileViews + liveViews == 0 {
            stopAll()
            return
        }
        if tileViews > 0 { startSnapshots() } else { stopSnapshots() }
        if wantsStream { startStream() } else { stopStream() }
    }

    // MARK: Snapshots

    private func startSnapshots() {
        guard snapshotTask == nil, let control = profile?.snapshotControl else { return }
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                control.takeSnapshot()
                try? await Task.sleep(for: Self.snapshotInterval)
                guard self != nil else { return }
            }
        }
    }

    private func stopSnapshots() {
        snapshotTask?.cancel()
        snapshotTask = nil
    }

    func cameraSnapshotControl(_ cameraSnapshotControl: HMCameraSnapshotControl,
                               didTake snapshot: HMCameraSnapshot?, error: (any Error)?) {
        if let snapshot, error == nil {
            self.snapshot = snapshot
            snapshotFailures = 0
            failed = false
        } else {
            snapshotFailures += 1
            if wantsStream { startStream() }
            failed = source == nil && stream == nil && !streamWanted
        }
    }

    // MARK: Stream

    private func startStream() {
        guard let control = profile?.streamControl else { return }
        streamWanted = true
        guard stream == nil, retryTask == nil else { return }
        errorText = nil
        control.startStream()
    }

    private func stopStream() {
        streamWanted = false
        retryTask?.cancel()
        retryTask = nil
        retryDelay = .seconds(3)
        guard stream != nil else { return }
        profile?.streamControl?.stopStream()
        stream = nil
    }

    private func stopAll() {
        stopSnapshots()
        stopStream()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = min(.seconds(60), retryDelay * 2)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            retryTask = nil
            if streamWanted { startStream() }
        }
    }

    func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) {
        stream = cameraStreamControl.cameraStream
        errorText = nil
        failed = false
        retryDelay = .seconds(3)
        if !streamWanted { stopStream() }
    }

    func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl, didStopStreamWithError error: (any Error)?) {
        stream = nil
        if let error {
            errorText = error.localizedDescription
        }
        if streamWanted {
            failed = snapshot == nil
            scheduleRetry()
        }
    }
}

/// One `CameraFeed` per camera for the life of the board, so a tile and the
/// full-screen view share a stream instead of competing for one.
@Observable
final class CameraFeedRegistry {
    static let shared = CameraFeedRegistry()
    private var feeds: [String: CameraFeed] = [:]

    func feed(for camera: CameraEntry) -> CameraFeed {
        if let feed = feeds[camera.id], feed.profile === camera.profile { return feed }
        let feed = CameraFeed(profile: camera.profile)
        feeds[camera.id] = feed
        return feed
    }
}
