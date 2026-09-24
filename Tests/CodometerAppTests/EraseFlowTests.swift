@testable import CodometerApp
import CodometerCore
import Foundation
import Testing

/// "Erase All Data": the order the steps run in, and the rule that nothing is written after the freeze.
@MainActor
@Suite("Erase flow")
struct EraseFlowTests {
    /// Records every step as it runs, so the order can be asserted.
    @MainActor
    final class Recorder {
        var steps: [String] = []
        var summary = EraseSummary(removedItems: 4, refusedSymlinks: 0, failures: 0)
        var leftovers = 2

        func operations() -> AppController.EraseOperations {
            AppController.EraseOperations(
                freeze: { self.steps.append("freeze") },
                stopWidgetExport: { self.steps.append("widget") },
                closeEngine: { self.steps.append("engine") },
                eraseDataRoot: {
                    self.steps.append("root")
                    return self.summary
                },
                unregisterLoginItem: { self.steps.append("loginItem") },
                removeNotifications: { self.steps.append("notifications") },
                removeDefaults: { self.steps.append("defaults") },
                removeSupportFiles: {
                    self.steps.append("leftovers")
                    return self.leftovers
                }
            )
        }
    }

    @Test("The steps run in one fixed order: freeze, widget, engine, data root, login item, notifications, defaults, leftovers")
    func order() async {
        let recorder = Recorder()
        _ = await AppController.runErase(recorder.operations())
        #expect(recorder.steps == ["freeze", "widget", "engine", "root", "loginItem", "notifications", "defaults", "leftovers"])
    }

    @Test("The freeze is first, so nothing can be written after it, and the database closes before the files go")
    func freezeComesFirst() async {
        let recorder = Recorder()
        _ = await AppController.runErase(recorder.operations())
        let freeze = recorder.steps.firstIndex(of: "freeze")
        let engine = recorder.steps.firstIndex(of: "engine")
        let root = recorder.steps.firstIndex(of: "root")
        #expect(freeze == 0)
        #expect(engine != nil && root != nil && engine! < root!)
        // The widget exporter stops before the data root goes, so a pending publish cannot recreate Widget/.
        #expect(recorder.steps.firstIndex(of: "widget")! < root!)
    }

    @Test("The summary counts the leftovers outside the data root with what the root erase removed")
    func summaryAddsLeftovers() async {
        let recorder = Recorder()
        recorder.summary = EraseSummary(removedItems: 9, refusedSymlinks: 1, failures: 2)
        recorder.leftovers = 2
        let summary = await AppController.runErase(recorder.operations())
        #expect(summary.removedItems == 11)
        #expect(summary.refusedSymlinks == 1)
        #expect(summary.failures == 2)
        #expect(!summary.isComplete)
    }

    @Test("A clean erase reports no refusals and no failures")
    func cleanErase() async {
        let recorder = Recorder()
        recorder.leftovers = 0
        let summary = await AppController.runErase(recorder.operations())
        #expect(summary.isComplete)
        #expect(summary.removedItems == 4)
    }

    @Test("Leftover folders are the app's own Caches and HTTPStorages, named by bundle id")
    func leftoverPaths() {
        let paths = AppSupportLeftovers.paths(bundleIdentifier: "com.codometer.Codometer", home: "/Users/tester")
        #expect(paths == [
            "/Users/tester/Library/Caches/com.codometer.Codometer",
            "/Users/tester/Library/HTTPStorages/com.codometer.Codometer",
        ])
    }

    @Test("An identifier that could name the Library folder itself yields no leftover paths")
    func leftoverPathsRefuseUnsafeIdentifiers() {
        for identifier in ["", ".", "..", "com", "com..app", "../Caches", "com.codometer/../..", "com.codometer.App "] {
            #expect(AppSupportLeftovers.paths(bundleIdentifier: identifier, home: "/Users/tester").isEmpty)
        }
        #expect(AppSupportLeftovers.isPlainIdentifier("com.codometer.Codometer"))
        #expect(AppSupportLeftovers.isPlainIdentifier("com.codometer.Codometer-dev"))
    }

    @Test("A leftover that is a symbolic link is never followed or removed")
    func leftoverSymlinkRefused() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-erase-\(UUID().uuidString)", isDirectory: true)
        let bundleIdentifier = "com.codometer.Test"
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let storages = home.appendingPathComponent("Library/HTTPStorages", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storages, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        // A real cache folder with a file in it, and a link where the HTTP storage would be.
        let realCache = caches.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try FileManager.default.createDirectory(at: realCache, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: realCache.appendingPathComponent("cache.bin"))
        let target = home.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target.appendingPathComponent("keep.txt"))
        try FileManager.default.createSymbolicLink(
            at: storages.appendingPathComponent(bundleIdentifier, isDirectory: true),
            withDestinationURL: target
        )

        let removed = AppSupportLeftovers.remove(bundleIdentifier: bundleIdentifier, home: home.path)
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: realCache.path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("keep.txt").path))
    }

    @Test("Nothing is removed when a leftover folder is not there")
    func leftoversMissing() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-erase-\(UUID().uuidString)", isDirectory: true).path
        #expect(AppSupportLeftovers.remove(bundleIdentifier: "com.codometer.Test", home: home) == 0)
    }

    @Test("Settings are not persisted while an erase is under way")
    func persistenceFrozen() {
        #expect(SettingsPersistence.plan(isReadOnly: false, isErasing: true, isDebugFixture: false) == .skip)
        #expect(SettingsPersistence.plan(isReadOnly: true, isErasing: true, isDebugFixture: false) == .skip)
        #expect(SettingsPersistence.plan(isReadOnly: false, isErasing: false, isDebugFixture: false) == .save)
    }
}

/// Where an export is written when something is already there.
@Suite("Export destination")
struct ExportDestinationTests {
    @Test("A free name is used as it is")
    func freeName() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Codometer History 2026-09-17.json")
        guard case .ready(let prepared) = ExportDestination.prepare(url) else {
            Issue.record("expected a free name")
            return
        }
        #expect(prepared == url)
    }

    @Test("An existing file goes to the Trash, never deleted, and the name is reused")
    func existingFileIsTrashed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Codometer History 2026-09-17.json")
        try Data("old".utf8).write(to: url)
        guard case .ready(let prepared) = ExportDestination.prepare(url) else {
            Issue.record("expected a prepared destination")
            return
        }
        #expect(prepared == url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A name that cannot be freed gets “ 2”, keeping the extension")
    func uniquedNames() {
        let json = URL(fileURLWithPath: "/tmp/Codometer History 2026-09-17.json")
        #expect(ExportDestination.uniqued(json, suffix: 2).lastPathComponent == "Codometer History 2026-09-17 2.json")
        let folder = URL(fileURLWithPath: "/tmp/Codometer History 2026-09-17", isDirectory: true)
        #expect(ExportDestination.uniqued(folder, suffix: 3).lastPathComponent == "Codometer History 2026-09-17 3")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
