@testable import CodometerApp
import CodometerCore
import Darwin
import Foundation
import Testing

/// Crash and hang payloads: at most five, at most 256 KB each, mode 0600, and nothing else in the folder touched.
@Suite("Crash payload store")
struct CrashPayloadStoreTests {
    private let start = Date(timeIntervalSince1970: 1_789_590_000)

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A file name says the kind and the moment, and reads back as the same summary")
    func namesRoundTrip() throws {
        for kind in CrashReportSummary.Kind.allCases {
            let name = CrashPayloadStore.fileName(kind: kind, date: start)
            let summary = try #require(CrashPayloadStore.summary(fileName: name))
            #expect(summary.kind == kind)
            #expect(summary.date == start)
            #expect(name == "\(summary.id).json")
        }
        #expect(CrashPayloadStore.fileName(kind: .crash, date: start) == "crash-20260916-202000.json")
    }

    @Test("Names that are not ours are ignored")
    func foreignNames() {
        #expect(CrashPayloadStore.summary(fileName: "settings.json") == nil)
        #expect(CrashPayloadStore.summary(fileName: "crash-20260916-202000.txt") == nil)
        #expect(CrashPayloadStore.summary(fileName: "crash-2026-09-16-202000.json") == nil)
        #expect(CrashPayloadStore.summary(fileName: "unknown-20260916-202000.json") == nil)
        #expect(CrashPayloadStore.summary(fileName: "crash-20261399-202000.json") == nil)
    }

    @Test("Only the oldest of our own files are dropped, never anything else")
    func rotationPlan() {
        var names = (0..<7).map { CrashPayloadStore.fileName(kind: .crash, date: start.addingTimeInterval(Double($0) * 3_600)) }
        names.append("settings.json")
        names.append("support.txt")
        let doomed = CrashPayloadStore.namesToDelete(from: names)
        #expect(doomed == Array(names.prefix(2)))
        #expect(CrashPayloadStore.namesToDelete(from: names, keeping: 7).isEmpty)
        #expect(CrashPayloadStore.namesToDelete(from: ["settings.json"]).isEmpty)
    }

    @Test("Stored payloads are private, capped in size, capped in number, newest first")
    func storing() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CrashPayloadStore(directory: folder)
        // A file that is not ours must survive every rotation.
        let stranger = folder.appendingPathComponent("support.txt", isDirectory: false)
        try Data("keep".utf8).write(to: stranger)

        for index in 0..<7 {
            let url = try #require(store.store(
                Data(repeating: UInt8(ascii: "{"), count: 10),
                kind: index.isMultiple(of: 2) ? .crash : .hang,
                date: start.addingTimeInterval(Double(index) * 3_600)
            ))
            var info = stat()
            #expect(lstat(url.path, &info) == 0)
            #expect(info.st_mode & 0o777 == 0o600)
        }

        let summaries = store.summaries()
        #expect(summaries.count == CrashPayloadStore.maximumPayloads)
        #expect(summaries == summaries.sorted { $0.date > $1.date })
        #expect(summaries.first?.date == start.addingTimeInterval(6 * 3_600))
        #expect(FileManager.default.fileExists(atPath: stranger.path))

        // Oversized payloads are cut to the cap.
        let big = try #require(store.store(
            Data(repeating: UInt8(ascii: "a"), count: CrashPayloadStore.maximumPayloadBytes + 5_000),
            kind: .exception,
            date: start.addingTimeInterval(8 * 3_600)
        ))
        #expect(try Data(contentsOf: big).count == CrashPayloadStore.maximumPayloadBytes)
        #expect(store.summaries().count == CrashPayloadStore.maximumPayloads)
    }

    @Test("The folder is created on demand, and listing an absent folder is empty rather than a failure")
    func missingFolder() throws {
        let folder = try makeFolder()
        let nested = folder.appendingPathComponent("Diagnostics", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CrashPayloadStore(directory: nested)
        #expect(store.summaries().isEmpty)
        store.prune()
        #expect(store.store(Data("{}".utf8), kind: .hang, date: start) != nil)
        #expect(store.summaries().count == 1)
    }
}
