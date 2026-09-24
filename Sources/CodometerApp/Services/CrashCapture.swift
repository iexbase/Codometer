import CodometerCore
import CodometerPlatform
import Foundation
import MetricKit
import os

/// Crash, hang and exception diagnostics kept on this Mac and nowhere else.
///
/// MetricKit hands the app a JSON payload after a crash or a hang. It holds binary UUIDs, addresses, the exception
/// type, the signal and the termination reason — no user content, no prompts, no paths of the user's projects — so it
/// is stored as it arrives, capped at `maximumPayloadBytes`, mode 0600, at most `maximumPayloads` files in
/// `<dataRoot>/Diagnostics/`. Nothing is ever uploaded.
struct CrashPayloadStore: Sendable {
    static let maximumPayloads = 5
    static let maximumPayloadBytes = 256 * 1024
    static let fileExtension = "json"
    /// Only names of this shape are listed or deleted, so nothing else in `Diagnostics/` is touched.
    static let namePrefixes: [CrashReportSummary.Kind: String] = [
        .crash: "crash", .hang: "hang", .exception: "exception",
    ]

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Names (pure)

    /// `crash-20260918-013000.json`: the kind, then the date in UTC, so the list sorts by name and a person can read it.
    static func fileName(kind: CrashReportSummary.Kind, date: Date) -> String {
        "\(namePrefixes[kind] ?? "crash")-\(stamp(date)).\(fileExtension)"
    }

    /// The summary a stored file's name stands for, or `nil` when the name is not one of ours.
    static func summary(fileName: String) -> CrashReportSummary? {
        guard fileName.hasSuffix("." + fileExtension) else { return nil }
        let stem = String(fileName.dropLast(fileExtension.count + 1))
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let kind = namePrefixes.first(where: { $0.value == parts[0] })?.key else { return nil }
        guard let date = date(day: String(parts[1]), time: String(parts[2])) else { return nil }
        return try? CrashReportSummary(id: stem, date: date, kind: kind)
    }

    /// Names to delete so that at most `keeping` of ours stay, oldest first. Names that are not ours are never listed.
    ///
    /// Sorted by the moment in the name, not by the name: a hang and a crash sort by kind first as text.
    static func namesToDelete(from names: [String], keeping: Int = maximumPayloads) -> [String] {
        let ours = names
            .compactMap { name -> (String, Date)? in summary(fileName: name).map { (name, $0.date) } }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map(\.0)
        guard ours.count > max(0, keeping) else { return [] }
        return Array(ours.prefix(ours.count - max(0, keeping)))
    }

    /// `yyyyMMdd-HHmmss` in UTC, built from calendar components so no locale is involved.
    private static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return "\(day)-\(time)"
    }

    private static func date(day: String, time: String) -> Date? {
        guard day.count == 8, time.count == 6, (day + time).allSatisfy(\.isNumber) else { return nil }
        func number(_ text: String, _ start: Int, _ length: Int) -> Int? {
            let from = text.index(text.startIndex, offsetBy: start)
            return Int(text[from..<text.index(from, offsetBy: length)])
        }
        var components = DateComponents()
        components.year = number(day, 0, 4)
        components.month = number(day, 4, 2)
        components.day = number(day, 6, 2)
        components.hour = number(time, 0, 2)
        components.minute = number(time, 2, 2)
        components.second = number(time, 4, 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: components) else { return nil }
        // `Calendar` rolls impossible components over (month 13 becomes next January), which would turn a stray file
        // name into a plausible date. Only a name that writes itself back unchanged is one of ours.
        return stamp(date) == "\(day)-\(time)" ? date : nil
    }

    // MARK: - Files

    /// Writes one payload and prunes the oldest beyond the cap. Returns the file it wrote, or `nil` when it could not.
    @discardableResult
    func store(_ payload: Data, kind: CrashReportSummary.Kind, date: Date) -> URL? {
        let bounded = payload.count > Self.maximumPayloadBytes ? payload.prefix(Self.maximumPayloadBytes) : payload
        let url = directory.appendingPathComponent(Self.fileName(kind: kind, date: date), isDirectory: false)
        do throws(FileAccessError) {
            try SecureFileIO.ensurePrivateDirectory(at: directory)
            try SecureFileIO.writeAtomically(Data(bounded), to: url, permissions: 0o600)
        } catch {
            AppLog.interface.error("crash payload not stored: \(error.summary, privacy: .public)")
            return nil
        }
        prune()
        return url
    }

    /// The stored reports, newest first.
    func summaries() -> [CrashReportSummary] {
        names().compactMap(Self.summary(fileName:)).sorted { $0.date > $1.date }
    }

    /// Deletes everything beyond the cap, oldest first.
    func prune() {
        for name in Self.namesToDelete(from: names()) {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            do throws(FileAccessError) {
                try SecureFileIO.unlinkRegularFile(at: url)
            } catch {
                AppLog.interface.notice("old crash payload not removed: \(error.summary, privacy: .public)")
            }
        }
    }

    private func names() -> [String] {
        (try? SecureFileIO.regularFileNames(in: directory)) ?? []
    }
}

/// Subscribes to MetricKit and stores what it sends.
///
/// MetricKit delivers on its own queue, at most once a day, and only after a crash or hang actually happened: there
/// is no polling and nothing runs while the app is idle.
final class CrashCapture: NSObject, MXMetricManagerSubscriber {
    private let store: CrashPayloadStore
    /// Serializes writes, which arrive on MetricKit's queue.
    private let queue = DispatchQueue(label: "com.codometer.app.crash-capture")
    private var isSubscribed = false

    init(store: CrashPayloadStore) {
        self.store = store
        super.init()
    }

    /// Makes AppKit turn an uncaught exception into a crash report instead of leaving the app half broken
    ///. The only defaults key Codometer registers besides the language override.
    static func enableCrashOnExceptions() {
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    }

    func start() {
        guard !isSubscribed else { return }
        isSubscribed = true
        store.prune()
        MXMetricManager.shared.add(self)
    }

    func stop() {
        guard isSubscribed else { return }
        isSubscribed = false
        MXMetricManager.shared.remove(self)
    }

    /// Usage metrics are of no interest: nothing is kept and nothing is sent.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let store = store
        // Only Sendable values cross the queue: the payload's own JSON and the kind.
        let items: [(Data, CrashReportSummary.Kind, Date)] = payloads.flatMap { payload -> [(Data, CrashReportSummary.Kind, Date)] in
            let date = payload.timeStampEnd
            var found: [(Data, CrashReportSummary.Kind, Date)] = []
            if payload.crashDiagnostics?.isEmpty == false {
                found.append((payload.jsonRepresentation(), .crash, date))
            } else if payload.hangDiagnostics?.isEmpty == false {
                found.append((payload.jsonRepresentation(), .hang, date))
            } else if payload.cpuExceptionDiagnostics?.isEmpty == false || payload.diskWriteExceptionDiagnostics?.isEmpty == false {
                found.append((payload.jsonRepresentation(), .exception, date))
            }
            return found
        }
        guard !items.isEmpty else { return }
        queue.async {
            for (data, kind, date) in items {
                store.store(data, kind: kind, date: date)
            }
        }
    }
}
