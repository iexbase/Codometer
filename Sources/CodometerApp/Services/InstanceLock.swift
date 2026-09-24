import CryptoKit
import Darwin
import Foundation

/// One running Codometer per data folder.
///
/// The lock is an advisory `flock` on `<dataRoot>/.lock`, opened with `O_NOFOLLOW` and mode 0600 and held for the
/// whole process lifetime. It is taken **after** the legacy migration and `AppDirectories.prepare()`: creating the
/// lock file first would make the new data root exist, and the migration would then leave the user's data behind
///.
///
/// A second copy that finds the lock busy posts a distributed notification scoped to that data root and quits; the
/// running copy hears only its own scoped name, so an isolated test instance can never make the user's app react.
final class InstanceLock {
    /// What an attempt to take the lock found.
    enum Acquisition {
        /// The lock is held by the returned object until it is released or the process exits.
        case acquired(InstanceLock)
        /// Another process holds the lock.
        case busy
        /// The lock file could not be opened at all (a symlink, wrong permissions, a missing folder). The launch
        /// goes on without a lock rather than refusing to start; `reason` is logged, never shown.
        case unavailable(reason: String)
    }

    let url: URL
    private var descriptor: Int32

    private init(descriptor: Int32, url: URL) {
        self.descriptor = descriptor
        self.url = url
    }

    deinit {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    /// Opens (or creates) the lock file privately and takes an exclusive, non-blocking `flock`.
    ///
    /// The file is never followed through a symbolic link, and an existing file's mode is tightened to 0600.
    static func acquire(at url: URL) -> Acquisition {
        let path = url.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            return .unavailable(reason: Self.reason(for: errno))
        }
        // A file left behind by an earlier version (or a careless umask) is tightened before it is used.
        if fchmod(descriptor, 0o600) != 0 {
            let code = errno
            Darwin.close(descriptor)
            return .unavailable(reason: Self.reason(for: code))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            return code == EWOULDBLOCK ? .busy : .unavailable(reason: Self.reason(for: code))
        }
        return .acquired(InstanceLock(descriptor: descriptor, url: url))
    }

    /// The `errno` in words, without the path (which names the user's home folder): safe for public log output.
    static func reason(for code: Int32) -> String {
        "\(String(cString: strerror(code))) (\(code))"
    }

    /// Releases the lock. Calling it twice does nothing the second time; `deinit` does the same.
    func release() {
        guard descriptor >= 0 else { return }
        let descriptor = descriptor
        self.descriptor = -1
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }

    // MARK: - The scoped "open settings" notification

    /// Prefix of the distributed notification a second copy posts; the data root's hash is appended.
    static let openSettingsNotificationPrefix = "com.codometer.Codometer.openSettings"

    /// `com.codometer.Codometer.openSettings.<first 8 hex of SHA-256(data root path)>`.
    ///
    /// Scoping by data root is what keeps an isolated test instance (`CODOMETER_DATA_ROOT`) from reaching the user's
    /// running app: the two never share a name.
    static func openSettingsNotificationName(dataRoot: URL) -> String {
        let digest = SHA256.hash(data: Data(dataRoot.standardizedFileURL.path.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(openSettingsNotificationPrefix).\(hex)"
    }
}

/// The `--relaunched-after <pid>` argument an in-app relaunch passes to its successor.
///
/// Without it the new copy would meet the old copy's lock and quit, so "Relaunch Codometer" and "Erase and Start
/// Over" could never work.
enum RelaunchArguments {
    static let flag = "--relaunched-after"

    /// The pid named by `--relaunched-after`, or `nil` when the argument is absent or not a plausible pid.
    static func predecessorPID(in arguments: [String]) -> pid_t? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        guard let value = Int32(arguments[index + 1]), value > 0 else { return nil }
        return pid_t(value)
    }
}

/// How a launch resolves a busy instance lock.
enum InstanceGateOutcome: Equatable {
    /// The lock was taken (possibly after waiting for the predecessor to exit).
    case acquired
    /// Another copy holds the lock: tell it to open Settings and quit.
    case busy
    /// No lock could be taken, and no other copy holds one either: go on unlocked.
    case unlocked(reason: String)
}

/// Takes the instance lock, with the one retry a relaunch needs.
///
/// Pure enough to test: the file work goes through `attempt`, and waiting for the predecessor through `waitForExit`,
/// so the tests drive both with real descriptors and no timers.
enum InstanceGate {
    /// How long a relaunched copy waits for its predecessor to exit before giving up.
    static let relaunchWait: TimeInterval = 5

    /// - Parameters:
    ///   - predecessor: The pid from `--relaunched-after`, or `nil` for an ordinary launch (which never waits).
    ///   - attempt: Tries to take the lock once.
    ///   - waitForExit: Waits up to the timeout for a pid to exit; `true` when it did.
    /// - Returns: The outcome and, when acquired, the lock to keep.
    static func acquire(
        predecessor: pid_t?,
        attempt: () -> InstanceLock.Acquisition,
        waitForExit: (pid_t, TimeInterval) -> Bool
    ) -> (outcome: InstanceGateOutcome, lock: InstanceLock?) {
        switch attempt() {
        case .acquired(let lock):
            return (.acquired, lock)
        case .unavailable(let reason):
            return (.unlocked(reason: reason), nil)
        case .busy:
            // Only a relaunch waits: an ordinary second copy must hand over at once.
            guard let predecessor, waitForExit(predecessor, relaunchWait) else { return (.busy, nil) }
            switch attempt() {
            case .acquired(let lock):
                return (.acquired, lock)
            case .unavailable(let reason):
                return (.unlocked(reason: reason), nil)
            case .busy:
                return (.busy, nil)
            }
        }
    }

    /// Waits for `pid` to exit using a process dispatch source (no polling loop); `true` when it exited (or was
    /// already gone) within `timeout`.
    static func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        // `kill(pid, 0)` answers "is that process still there" without sending a signal.
        guard kill(pid, 0) == 0 || errno == EPERM else { return true }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        let exited = DispatchSemaphore(value: 0)
        source.setEventHandler { exited.signal() }
        source.resume()
        defer { source.cancel() }
        // The process may have exited between the check and the source being armed.
        if kill(pid, 0) != 0, errno != EPERM {
            return true
        }
        return exited.wait(timeout: .now() + timeout) == .success
    }
}
