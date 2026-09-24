@testable import CodometerApp
import Darwin
import Foundation
import Testing

/// The single-instance lock: one holder per data folder, private files, and no symlink ever followed.
@Suite("Instance lock")
struct InstanceLockTests {
    /// A fresh folder that goes away with the test.
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mode(of url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_mode & 0o777
    }

    @Test("A second lock on the same data folder is busy until the first one is released")
    func sameFolderIsBusy() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".lock", isDirectory: false)

        guard case .acquired(let first) = InstanceLock.acquire(at: file) else {
            Issue.record("the first lock was not acquired")
            return
        }
        if case .busy = InstanceLock.acquire(at: file) {} else {
            Issue.record("the second lock should have found the file busy")
        }
        first.release()
        guard case .acquired(let third) = InstanceLock.acquire(at: file) else {
            Issue.record("the lock should be free again after release()")
            return
        }
        third.release()
        // Releasing twice is harmless.
        third.release()
    }

    @Test("Locks in different data folders never see each other")
    func differentFoldersAreIndependent() throws {
        let one = try makeFolder()
        let two = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: one)
            try? FileManager.default.removeItem(at: two)
        }
        guard case .acquired(let a) = InstanceLock.acquire(at: one.appendingPathComponent(".lock")),
              case .acquired(let b) = InstanceLock.acquire(at: two.appendingPathComponent(".lock")) else {
            Issue.record("two data folders must both be lockable")
            return
        }
        a.release()
        b.release()
    }

    @Test("The lock file is created 0600, and an existing looser file is tightened")
    func lockFileIsPrivate() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".lock", isDirectory: false)

        guard case .acquired(let lock) = InstanceLock.acquire(at: file) else {
            Issue.record("not acquired")
            return
        }
        #expect(mode(of: file) == 0o600)
        lock.release()

        #expect(chmod(file.path, 0o644) == 0)
        guard case .acquired(let again) = InstanceLock.acquire(at: file) else {
            Issue.record("not acquired the second time")
            return
        }
        #expect(mode(of: file) == 0o600)
        again.release()
    }

    @Test("A symlink in place of the lock file is refused, and nothing is written through it")
    func symlinkIsRefused() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("target.txt", isDirectory: false)
        try Data("keep me".utf8).write(to: target)
        let file = folder.appendingPathComponent(".lock", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

        guard case .unavailable(let reason) = InstanceLock.acquire(at: file) else {
            Issue.record("a symlinked lock file must not be opened")
            return
        }
        #expect(!reason.isEmpty)
        #expect(try Data(contentsOf: target) == Data("keep me".utf8))
    }

    @Test("The “open settings” notification name is scoped to the data folder")
    func notificationNameIsScoped() {
        let one = URL(fileURLWithPath: "/tmp/one", isDirectory: true)
        let two = URL(fileURLWithPath: "/tmp/two", isDirectory: true)
        let first = InstanceLock.openSettingsNotificationName(dataRoot: one)
        let second = InstanceLock.openSettingsNotificationName(dataRoot: two)

        #expect(first != second)
        #expect(first == InstanceLock.openSettingsNotificationName(dataRoot: one))
        #expect(first.hasPrefix(InstanceLock.openSettingsNotificationPrefix + "."))
        let suffix = first.dropFirst(InstanceLock.openSettingsNotificationPrefix.count + 1)
        #expect(suffix.count == 8)
        #expect(suffix.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        // A trailing slash names the same folder.
        #expect(InstanceLock.openSettingsNotificationName(dataRoot: URL(fileURLWithPath: "/tmp/one/")) == first)
    }
}
