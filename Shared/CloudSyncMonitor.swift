import CloudKit
import CoreData
import Foundation
import Observation

/// What the CloudKit mirror underneath SwiftData is actually doing. A local
/// save always succeeds, so without this the iPhone says "Published" while
/// nothing reaches iCloud, and the Apple TV has no way to tell a quiet day
/// from a broken sync. SwiftData posts Core Data's sync events; this keeps
/// the last outcome of each kind.
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    /// When the last download from iCloud finished successfully.
    private(set) var lastImport: Date?
    /// When the last upload to iCloud finished successfully.
    private(set) var lastExport: Date?
    private(set) var importError: String?
    private(set) var exportError: String?
    private(set) var setupError: String?
    /// True once the first download of this launch has ended, well or badly.
    /// Until then the local store may simply not have caught up with iCloud.
    private(set) var initialImportDone = false

    /// How a wait for an upload ended.
    enum ExportResult: Sendable { case uploaded, failed, timedOut, notSyncing }

    /// When the most recent upload that has ended began, and how it ended.
    /// Whatever was saved before it began was part of it.
    @ObservationIgnored private var lastExportBegan: Date?
    @ObservationIgnored private var lastExportSucceeded = false

    private struct ExportWaiter {
        var id: UUID
        var saved: Date
        var continuation: CheckedContinuation<ExportResult, Never>
    }
    @ObservationIgnored private var exportWaiters: [ExportWaiter] = []

    private var observer: NSObjectProtocol?

    private struct Outcome: Sendable {
        var kind: Int
        var started: Date
        var finished: Date?
        var succeeded: Bool
        var message: String?
    }

    private init() {}

    /// Call before the model container is first touched so no event is missed.
    func start() {
        guard observer == nil, !LookoutStore.isDemo else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let kind: Int
            switch event.type {
            case .setup: kind = 0
            case .import: kind = 1
            case .export: kind = 2
            @unknown default: kind = -1
            }
            let outcome = Outcome(kind: kind, started: event.startDate, finished: event.endDate,
                                  succeeded: event.succeeded,
                                  message: event.error.map(CloudSyncMonitor.describe))
            Task { @MainActor [weak self] in self?.apply(outcome) }
        }
    }

    private func apply(_ outcome: Outcome) {
        // An event is posted when it starts and again when it ends.
        guard let finished = outcome.finished else { return }
        switch outcome.kind {
        case 0:
            setupError = outcome.succeeded ? nil : outcome.message
            // No account or no network: there will be no import to wait for,
            // and no upload either.
            if !outcome.succeeded {
                initialImportDone = true
                endExportWaits(.failed) { _ in true }
            }
        case 1:
            if outcome.succeeded { lastImport = finished }
            importError = outcome.succeeded ? nil : outcome.message
            initialImportDone = true
        case 2:
            if outcome.succeeded { lastExport = finished }
            exportError = outcome.succeeded ? nil : outcome.message
            lastExportBegan = outcome.started
            lastExportSucceeded = outcome.succeeded
            endExportWaits(outcome.succeeded ? .uploaded : .failed) { $0.saved <= outcome.started }
        default:
            break
        }
    }

    /// Returns once the first download of this launch has ended, or after
    /// `timeout` seconds when iCloud is slow or unreachable.
    func waitForInitialImport(timeout: Double) async {
        guard !LookoutStore.isDemo, observer != nil,
              LookoutStore.mode != .localOnly, LookoutStore.mode != .memory else { return }
        let deadline = Date.now.addingTimeInterval(timeout)
        while !initialImportDone, Date.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// False when nothing saved on this device can reach iCloud right now:
    /// demo data, a store opened without iCloud, or no account.
    private var canExport: Bool {
        !LookoutStore.isDemo && observer != nil && setupError == nil
            && LookoutStore.mode != .localOnly && LookoutStore.mode != .memory
    }

    /// True while something saved at `saved` is still waiting for an upload:
    /// none that began after it has ended yet.
    func isAwaitingExport(of saved: Date) -> Bool {
        guard canExport else { return false }
        if let began = lastExportBegan, began >= saved { return false }
        return true
    }

    /// Returns once an upload that began after `saved` has ended, so what
    /// was saved then is in iCloud or has failed to get there, or after
    /// `timeout` seconds. A local save returns long before that, and iOS
    /// suspends an app in the background as soon as it says it is done.
    /// Nothing is polled: the mirror's own events end the wait.
    func waitForExport(of saved: Date, timeout: Double) async -> ExportResult {
        guard canExport else { return setupError == nil ? .notSyncing : .failed }
        if let began = lastExportBegan, began >= saved {
            return lastExportSucceeded ? .uploaded : .failed
        }
        guard timeout > 0, !Task.isCancelled else { return .timedOut }
        let id = UUID()
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { self?.endExportWaits(.timedOut) { $0.id == id } }
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                exportWaiters.append(ExportWaiter(id: id, saved: saved, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.endExportWaits(.timedOut) { $0.id == id } }
        }
    }

    private func endExportWaits(_ result: ExportResult, where matches: (ExportWaiter) -> Bool) {
        let ended = exportWaiters.filter(matches)
        guard !ended.isEmpty else { return }
        exportWaiters.removeAll(where: matches)
        for waiter in ended {
            waiter.continuation.resume(returning: result)
        }
    }

    /// A sentence a person can act on, for the errors that are theirs to fix.
    nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .quotaExceeded:
                return String(localized: "Your iCloud storage is full.")
            case .notAuthenticated:
                return String(localized: "This device is not signed in to iCloud.")
            case .networkUnavailable, .networkFailure:
                return String(localized: "iCloud could not be reached.")
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return String(localized: "iCloud is busy. It will try again shortly.")
            case .partialFailure:
                let inner = (nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.values.first
                if let inner, (inner as NSError).code != CKError.Code.partialFailure.rawValue {
                    return describe(inner)
                }
            default:
                break
            }
        }
        // Core Data reports a missing account in its own domain, with the
        // CloudKit status only in the text.
        let reason = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String) ?? ""
        if reason.contains("CKAccountStatusNoAccount") {
            return String(localized: "This device is not signed in to iCloud.")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            let inner = underlying as NSError
            if inner.domain == CKErrorDomain { return describe(underlying) }
        }
        return nsError.localizedDescription
    }
}
