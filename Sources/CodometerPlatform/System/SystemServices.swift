import Darwin
import Foundation
import Network
import Synchronization
import os

public enum AppLog {
    public static let subsystem = "com.codometer.app"

    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let claude = Logger(subsystem: subsystem, category: "claude")
    public static let codex = Logger(subsystem: subsystem, category: "codex")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let interface = Logger(subsystem: subsystem, category: "interface")
}

/// Liveness and start-time checks for other processes.
public enum ProcessInspector {
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Kernel start time, used to tell a live process from a later one that reused its PID.
    public static func startTime(of pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let status = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, UInt32(buffer.count), &info, &size, nil, 0)
        }
        guard status == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

/// What the current network path allows: whether it works at all, and whether it is one the user would rather not
/// spend (a personal hotspot, or a link macOS marks as constrained under Low Data Mode).
public struct NetworkReachability: Hashable, Sendable {
    public static let assumedAvailable = NetworkReachability(isOnline: true, isConstrained: false, isExpensive: false)

    public let isOnline: Bool
    public let isConstrained: Bool
    public let isExpensive: Bool

    public init(isOnline: Bool, isConstrained: Bool, isExpensive: Bool) {
        self.isOnline = isOnline
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }
}

/// Whether any network path is available, so the app does not spawn probes that cannot succeed.
///
/// Event-driven: `NWPathMonitor` reports changes, nothing polls. Before `start()` (and for a monitor that is never
/// started) the path is assumed available, which is what the probes expect.
public final class NetworkStatusMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "codometer.network", qos: .utility)
    private let path = Mutex(NetworkReachability.assumedAvailable)

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.path.withLock {
                $0 = NetworkReachability(
                    isOnline: path.status == .satisfied,
                    isConstrained: path.isConstrained,
                    isExpensive: path.isExpensive
                )
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    /// The whole picture in one read, so a decision never mixes two moments.
    public var reachability: NetworkReachability {
        path.withLock { $0 }
    }

    public var isOnline: Bool {
        reachability.isOnline
    }

    /// The path is metered or the user asked for Low Data Mode: the opt-in status check stays off.
    public var isConstrained: Bool {
        reachability.isConstrained
    }

    /// A personal hotspot or another link macOS marks as expensive.
    public var isExpensive: Bool {
        reachability.isExpensive
    }
}

/// Builds child environments from scratch so nothing from the app's own environment leaks in
/// (for example `CLAUDECODE` when the app was started from inside a Claude Code session).
public enum ChildEnvironment {
    public static func minimal(homeDirectory: String, adding extra: [String: String] = [:]) -> [String: String] {
        let user = NSUserName()
        var environment = [
            "HOME": homeDirectory,
            "USER": user,
            "LOGNAME": user,
            "SHELL": "/bin/zsh",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TMPDIR": NSTemporaryDirectory(),
            "TERM": "dumb",
            "NO_COLOR": "1",
        ]
        environment.merge(extra) { _, new in new }
        return environment
    }
}
