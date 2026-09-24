import CodometerCore
@testable import CodometerPlatform
import Darwin
import Foundation
import Testing

/// A data root filled with every file the app creates, so an erase has something to remove.
private struct DataRoot {
    let directory: TemporaryDirectory
    let directories: AppDirectories

    init() throws {
        directory = try TemporaryDirectory()
        directories = AppDirectories(root: directory.url.appendingPathComponent("Codometer", isDirectory: true))
        try directories.prepare()
        for name in [
            "settings.json", "settings.invalid-1789599900.json", "settings.backup-repair-1789599900.json",
            "settings.backup-0.9.0.json", "history.sqlite", "history.sqlite-wal", "history.sqlite-shm",
            "history.sqlite-journal", "history.corrupt-1789599900.sqlite", "history.corrupt-1789599900.sqlite-wal",
            ".lock", "Codometer History.json.partial",
        ] {
            try write(name)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Widget"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Diagnostics"), withIntermediateDirectories: true)
        try write("Widget/snapshot.json")
        try write("Widget/snapshot.json.tmp")
        try write("Diagnostics/payload-1.json")
    }

    var root: URL { directories.root }

    func write(_ relativePath: String, contents: String = "{}") throws {
        try Data(contents.utf8).write(to: root.appendingPathComponent(relativePath))
    }

    var entries: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path).sorted()) ?? []
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }
}

@Suite("Erase all data")
struct AppDirectoriesEraseTests {
    @Test("Every file the app writes is removed, and the empty root with it")
    func erasesEverything() throws {
        let data = try DataRoot()
        let summary = try data.directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil)
        #expect(summary.isComplete)
        // 12 files in the root, 3 inside Widget and Diagnostics, those two folders, probe, and the root itself.
        #expect(summary.removedItems == 19)
        #expect(summary.refusedSymlinks == 0)
        #expect(data.exists == false)
    }

    @Test("Erasing an already empty or missing root is a no-op that still removes it")
    func missingRoot() throws {
        let directory = try TemporaryDirectory()
        let directories = AppDirectories(root: directory.url.appendingPathComponent("gone", isDirectory: true))
        #expect(try directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil) == EraseSummary(removedItems: 0, refusedSymlinks: 0, failures: 0))

        try directories.prepare()
        let summary = try directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil)
        // The root and the probe folder it creates.
        #expect(summary.removedItems == 2)
        #expect(summary.isComplete)
    }

    @Test("A symbolic link inside Widget is neither followed nor removed, and its target survives")
    func refusesSymlinkInsideWidget() throws {
        let data = try DataRoot()
        let outside = data.directory.file("precious.txt")
        try Data("keep me".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: data.root.appendingPathComponent("Widget/escape.json"),
            withDestinationURL: outside
        )

        let summary = try data.directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil)
        #expect(summary.refusedSymlinks == 1)
        #expect(summary.isComplete == false)
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep me")
        // The root stays, because something inside could not be removed.
        #expect(data.exists)
        #expect(data.entries == ["Widget"])
    }

    @Test("A symlinked data root is refused outright")
    func refusesSymlinkedRoot() throws {
        let directory = try TemporaryDirectory()
        let real = directory.url.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: real.appendingPathComponent("settings.json"))
        let link = directory.url.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let directories = AppDirectories(root: link)
        #expect(throws: FileAccessError.notRegularFile(path: link.path)) {
            _ = try directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil)
        }
        #expect(FileManager.default.fileExists(atPath: real.appendingPathComponent("settings.json").path))
    }

    @Test("An entry the app never wrote is left alone and keeps the root")
    func keepsUnknownEntries() throws {
        let data = try DataRoot()
        try data.write("notes.txt", contents: "mine")
        try FileManager.default.createDirectory(at: data.root.appendingPathComponent("Screenshots"), withIntermediateDirectories: true)

        let summary = try data.directories.eraseAll(bundleIdentifier: nil, savedStateParent: nil)
        #expect(summary.isComplete == false)
        #expect(summary.failures == 2)
        #expect(data.exists)
        #expect(data.entries == ["Screenshots", "notes.txt"])
    }

    @Test("The app's saved window state goes too, and only when the bundle identifier names it")
    func savedState() throws {
        let data = try DataRoot()
        let parent = data.directory.url.appendingPathComponent("Saved Application State", isDirectory: true)
        let saved = parent.appendingPathComponent("com.codometer.Codometer.savedState", isDirectory: true)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        try Data("windows".utf8).write(to: saved.appendingPathComponent("windows.plist"))

        let summary = try data.directories.eraseAll(bundleIdentifier: "com.codometer.Codometer", savedStateParent: parent)
        #expect(summary.isComplete)
        #expect(FileManager.default.fileExists(atPath: saved.path) == false)
        #expect(FileManager.default.fileExists(atPath: parent.path))
    }

    @Test("A bundle identifier that could name something else is ignored")
    func rejectsOddIdentifiers() {
        #expect(AppDirectories.savedStateName(for: "com.codometer.Codometer") == "com.codometer.Codometer.savedState")
        #expect(AppDirectories.savedStateName(for: nil) == nil)
        #expect(AppDirectories.savedStateName(for: "") == nil)
        #expect(AppDirectories.savedStateName(for: "..") == nil)
        #expect(AppDirectories.savedStateName(for: "../../etc") == nil)
        #expect(AppDirectories.savedStateName(for: "a/b") == nil)
    }

    @Test("Only names the app writes count as erasable")
    func erasableNames() {
        for name in [
            "settings.json", "settings.invalid-1.json", "settings.backup-1.0.0.json", "history.sqlite",
            "history.sqlite-wal", "history.sqlite-shm", "history.sqlite-journal", "history.corrupt-1.sqlite",
            "history.corrupt-1.sqlite-wal", ".lock", "export.partial", "snapshot.json.tmp",
        ] {
            #expect(AppDirectories.isErasableFile(name), "\(name) should be erasable")
        }
        for name in ["notes.txt", "settings.invalid-", ".partial", ".tmp", "history.sqlite.backup", ".DS_Store", ""] {
            #expect(AppDirectories.isErasableFile(name) == false, "\(name) should not be erasable")
        }
    }
}
