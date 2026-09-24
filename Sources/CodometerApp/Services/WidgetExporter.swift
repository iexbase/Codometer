import CodometerCore
import CodometerL10n
import CodometerPlatform
import Darwin
import Foundation
import os
import WidgetKit

/// Keeps the desktop widget's snapshot file current.
///
/// `update` is cheap and may be called on every state change and clock tick: it builds the snapshot and lets
/// `WidgetExportPolicy` decide when to publish it. Identical content is skipped; significant changes are published
/// within a minute; routine ones wait up to a quarter of an hour, because every publish asks WidgetKit for a
/// timeline reload and the system allows only a few dozen a day. A waiting change is published by one sleeping task
/// with the newest snapshot at that moment. Publishing replaces the file atomically in a private (`0700`) folder
/// with owner-only (`0600`) permissions — the widget extension runs as the same user and reads it through its
/// sandbox exception — and then reloads the widget. When the user turns the export off the file is deleted, so the
/// widget shows "No data" instead of numbers that silently age.
@MainActor
final class WidgetExporter {
    /// How long a failed write waits before the next attempt.
    static let retryInterval: TimeInterval = 60

    let directory: URL
    let fileURL: URL
    /// `false` for an isolated data root: nothing is written, removed or reloaded.
    let isEnabled: Bool

    private var policy = WidgetExportPolicy()
    private let writer: Writer
    /// Orders file operations: a newer one is never undone by an older one that reached the writer late.
    private var generation: UInt64 = 0
    /// Whether the last update exported data; `nil` before the first update, so a stale file is removed on launch.
    private var isExporting: Bool?
    /// The newest snapshot, published when a waiting change comes due.
    private var latest: WidgetSnapshot?
    private var pendingPublish: Task<Void, Never>?
    private var pendingDue: Date?
    private var retryNotBefore: Date?
    /// Set by `removeSnapshotForErase()`: nothing is exported again in this run.
    private var isErased = false
    /// `WidgetCenter` needs a bundled app with an embedded extension; `swift run` builds have no bundle identifier.
    private let canReloadTimelines = Bundle.main.bundleIdentifier != nil

    init(directory: URL, isEnabled: Bool = true) {
        self.directory = directory
        self.isEnabled = isEnabled
        fileURL = directory.appendingPathComponent(WidgetSnapshot.fileName, isDirectory: false)
        writer = Writer(directory: directory, fileURL: fileURL)
    }

    /// `language` is the app's resolved interface language: titles and notices are written in it, and the extension
    /// renders its own text in it. A language change alone is new content and gets published.
    func update(state: TrackerState, settings: AppSettings, language: Language, now: Date) {
        guard isEnabled, !isErased else { return }
        guard settings.general.exportsWidgetData else {
            stopExporting()
            return
        }
        guard WidgetSnapshot.isStateReady(state, for: settings) else { return }
        isExporting = true
        latest = WidgetSnapshot.make(state: state, settings: settings, now: now, language: language)
        evaluate(now: now)
    }

    /// "Erase All Data": stops exporting, deletes the snapshot file and reloads every widget kind, so widgets show
    /// "No data" instead of numbers. Later updates are ignored until the app relaunches.
    func removeSnapshotForErase() {
        guard isEnabled else { return }
        isErased = true
        latest = nil
        retryNotBefore = nil
        cancelPendingPublish()
        policy.reset()
        generation &+= 1
        let generation = generation
        let writer = writer
        Task { [weak self] in
            _ = await writer.remove(generation: generation)
            self?.reloadTimelines()
        }
    }

    /// Asks WidgetKit to reload every widget kind now (after an update of the app, whose widget kinds may be new).
    func forceReload() {
        guard isEnabled else { return }
        reloadTimelines()
    }

    private func evaluate(now: Date) {
        guard let latest else { return }
        if let retryNotBefore, now < retryNotBefore { return }
        switch policy.decision(for: latest, now: now) {
        case .skipIdentical:
            cancelPendingPublish()
        case .publish:
            cancelPendingPublish()
            publish(latest, now: now)
        case .wait(let due):
            schedulePublish(at: due, now: now)
        }
    }

    /// One sleeping task at most; an earlier due date replaces a later one.
    private func schedulePublish(at due: Date, now: Date) {
        if pendingPublish != nil, let pendingDue, pendingDue <= due { return }
        cancelPendingPublish()
        pendingDue = due
        let delay = max(0, due.timeIntervalSince(now))
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.pendingPublish = nil
            self.pendingDue = nil
            self.evaluate(now: Date())
        }
    }

    private func cancelPendingPublish() {
        pendingPublish?.cancel()
        pendingPublish = nil
        pendingDue = nil
    }

    private func publish(_ snapshot: WidgetSnapshot, now: Date) {
        let data: Data
        do {
            data = try snapshot.encodedData()
        } catch {
            AppLog.storage.error("widget snapshot not encoded: \(String(describing: error), privacy: .public)")
            return
        }
        guard data.count <= WidgetSnapshot.maximumFileBytes else {
            AppLog.storage.error("widget snapshot too large: \(data.count, privacy: .public) bytes")
            return
        }
        policy.recordPublish(snapshot, at: now)
        retryNotBefore = nil
        generation &+= 1
        let generation = generation
        let writer = writer
        Task { [weak self] in
            switch await writer.write(data, generation: generation) {
            case .done: self?.reloadTimelines()
            case .failed: self?.publishFailed(generation: generation)
            case .superseded: break
            }
        }
    }

    /// Forgets the failed publish so the newest content is tried again after `retryInterval`.
    private func publishFailed(generation: UInt64) {
        guard generation == self.generation else { return }
        policy.reset()
        retryNotBefore = Date().addingTimeInterval(Self.retryInterval)
    }

    private func stopExporting() {
        guard isExporting != false else { return }
        isExporting = false
        latest = nil
        retryNotBefore = nil
        cancelPendingPublish()
        policy.reset()
        generation &+= 1
        let generation = generation
        let writer = writer
        Task { [weak self] in
            if await writer.remove(generation: generation) == .done {
                self?.reloadTimelines()
            }
        }
    }

    /// Every kind reads the same file: "AI Limits", "Claude" and "Codex".
    private func reloadTimelines() {
        guard canReloadTimelines else { return }
        for kind in WidgetSnapshot.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}

extension WidgetExporter {
    private enum Outcome: Sendable {
        case done
        /// The file operation failed, or there was no file to remove.
        case failed
        /// A newer operation already ran.
        case superseded
    }

    /// File I/O off the main actor. Operations carry the exporter's generation and are dropped when a newer
    /// one already ran, because unstructured tasks may reach the actor out of order.
    private actor Writer {
        private let directory: URL
        private let fileURL: URL
        private var appliedGeneration: UInt64 = 0

        init(directory: URL, fileURL: URL) {
            self.directory = directory
            self.fileURL = fileURL
        }

        func write(_ data: Data, generation: UInt64) -> Outcome {
            guard generation > appliedGeneration else { return .superseded }
            appliedGeneration = generation
            do throws(FileAccessError) {
                try SecureFileIO.ensurePrivateDirectory(at: directory)
                try SecureFileIO.writeAtomically(data, to: fileURL, permissions: 0o600)
                return .done
            } catch {
                AppLog.storage.error("widget snapshot not written: \(error.summary, privacy: .public) (\(error.description, privacy: .private))")
                return .failed
            }
        }

        /// `.done` only when a snapshot file existed and was removed.
        func remove(generation: UInt64) -> Outcome {
            guard generation > appliedGeneration else { return .superseded }
            appliedGeneration = generation
            guard unlink(fileURL.path) == 0 else {
                let code = errno
                if code != ENOENT {
                    let path = fileURL.path
                    let failure = FileAccessError.ioFailure(path: path, code: code)
                    AppLog.storage.error("widget snapshot not removed: \(failure.summary, privacy: .public) (\(failure.description, privacy: .private))")
                }
                return .failed
            }
            return .done
        }
    }
}
