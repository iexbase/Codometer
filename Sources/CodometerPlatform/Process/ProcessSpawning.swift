import Darwin
import Dispatch
import Foundation

public struct ProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    /// The complete child environment. Nothing is inherited from the app.
    public let environment: [String: String]
    public let workingDirectory: URL

    public init(executable: URL, arguments: [String], environment: [String: String], workingDirectory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public enum ProcessExit: Hashable, Sendable {
    case exited(code: Int32)
    case signaled(signal: Int32)

    public var isSuccess: Bool { self == .exited(code: 0) }

    init(waitStatus status: Int32) {
        let low = status & 0x7f
        if low == 0 {
            self = .exited(code: (status >> 8) & 0xff)
        } else {
            self = .signaled(signal: low)
        }
    }
}

public enum ProcessRunError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidRequest(reason: String)
    case spawnFailed(code: Int32)
    case pipeFailed(code: Int32)
    case timedOut(seconds: Double)
    case outputTooLarge(limit: Int)
    case cancelled

    public var description: String {
        switch self {
        case .invalidRequest(let reason): "invalid process request: \(reason)"
        case .spawnFailed(let code): "could not start process: \(String(cString: strerror(code)))"
        case .pipeFailed(let code): "could not create pipe: \(String(cString: strerror(code)))"
        case .timedOut(let seconds): "process did not finish within \(seconds) s"
        case .outputTooLarge(let limit): "process output exceeded \(limit) bytes"
        case .cancelled: "process was cancelled"
        }
    }
}

/// A freshly spawned child and the parent's ends of its pipes.
struct SpawnedChild: Sendable {
    let pid: pid_t
    let standardInput: Int32?
    let standardOutput: Int32
    let standardError: Int32
}

enum Spawner {
    /// Starts the child in its own process group with only stdin/stdout/stderr inherited,
    /// default signal handlers, an explicit environment and a fixed working directory.
    static func spawn(_ request: ProcessRequest, connectsStandardInput: Bool) throws(ProcessRunError) -> SpawnedChild {
        try validate(request)

        let output = try makePipe()
        let errors: (read: Int32, write: Int32)
        do throws(ProcessRunError) {
            errors = try makePipe()
        } catch {
            closeAll(output.read, output.write)
            throw error
        }
        var input: (read: Int32, write: Int32)?
        if connectsStandardInput {
            do throws(ProcessRunError) {
                input = try makePipe()
            } catch {
                closeAll(output.read, output.write, errors.read, errors.write)
                throw error
            }
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let input {
            posix_spawn_file_actions_adddup2(&actions, input.read, STDIN_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, output.write, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors.write, STDERR_FILENO)
        posix_spawn_file_actions_addchdir(&actions, request.workingDirectory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaultSignals: sigset_t = ~sigset_t(0)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var emptyMask: sigset_t = 0
        posix_spawnattr_setsigmask(&attributes, &emptyMask)

        let argumentStrings = [request.executable.path] + request.arguments
        let environmentStrings = request.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let argv = argumentStrings.map { strdup($0) } + [nil]
        let envp = environmentStrings.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, request.executable.path, &actions, &attributes, argv, envp)

        closeAll(output.write, errors.write)
        if let input { closeAll(input.read) }

        guard status == 0 else {
            closeAll(output.read, errors.read)
            if let input { closeAll(input.write) }
            throw .spawnFailed(code: status)
        }
        if let input {
            _ = fcntl(input.write, F_SETNOSIGPIPE, 1)
        }
        return SpawnedChild(
            pid: pid,
            standardInput: input?.write,
            standardOutput: output.read,
            standardError: errors.read
        )
    }

    /// Terminates the whole process group, so helpers the child started do not linger.
    static func signalGroup(of pid: pid_t, _ signal: Int32) {
        guard pid > 0 else { return }
        _ = kill(-pid, signal)
        _ = kill(pid, signal)
    }

    /// Blocks the calling thread until the child exits; call from a dedicated queue.
    static func waitForExit(of pid: pid_t) -> ProcessExit {
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, 0)
            if result == pid { return ProcessExit(waitStatus: status) }
            if result == -1 && errno == EINTR { continue }
            return .signaled(signal: SIGKILL)
        }
    }

    private static func validate(_ request: ProcessRequest) throws(ProcessRunError) {
        guard request.executable.isFileURL, request.executable.path.hasPrefix("/") else {
            throw .invalidRequest(reason: "executable must be an absolute file path")
        }
        guard request.workingDirectory.path.hasPrefix("/") else {
            throw .invalidRequest(reason: "working directory must be absolute")
        }
        let values = request.arguments + request.environment.keys + request.environment.values
            + [request.executable.path, request.workingDirectory.path]
        guard !values.contains(where: { $0.utf8.contains(0) }) else {
            throw .invalidRequest(reason: "arguments and environment must not contain NUL bytes")
        }
        guard !request.environment.keys.contains(where: { $0.isEmpty || $0.contains("=") }) else {
            throw .invalidRequest(reason: "invalid environment variable name")
        }
    }

    private static func makePipe() throws(ProcessRunError) -> (read: Int32, write: Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw .pipeFailed(code: errno) }
        for descriptor in descriptors {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
        return (descriptors[0], descriptors[1])
    }

    private static func closeAll(_ descriptors: Int32...) {
        for descriptor in descriptors where descriptor >= 0 {
            close(descriptor)
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    var dispatchInterval: DispatchTimeInterval {
        .milliseconds(Int((timeInterval * 1_000).rounded(.up)))
    }
}
