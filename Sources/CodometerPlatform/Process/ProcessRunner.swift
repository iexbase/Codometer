import Darwin
import Dispatch
import Foundation
import Synchronization

public struct ProcessResult: Sendable {
    public let processID: Int32
    public let exit: ProcessExit
    public let standardOutput: Data
    public let standardError: Data
}

/// Process IDs the app itself started, so monitors can ignore sessions they created.
public final class ChildProcessRegistry: Sendable {
    private let processIDs = Mutex<Set<Int32>>([])

    public init() {}

    public func insert(_ pid: Int32) {
        processIDs.withLock { _ = $0.insert(pid) }
    }

    public func remove(_ pid: Int32) {
        processIDs.withLock { _ = $0.remove(pid) }
    }

    public func contains(_ pid: Int32) -> Bool {
        processIDs.withLock { $0.contains(pid) }
    }
}

/// Runs a short-lived command to completion with a timeout and an output cap.
public struct ProcessRunner: Sendable {
    private let registry: ChildProcessRegistry?

    public init(registry: ChildProcessRegistry? = nil) {
        self.registry = registry
    }

    public func run(
        _ request: ProcessRequest,
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws(ProcessRunError) -> ProcessResult {
        precondition(maximumOutputBytes > 0, "output cap must be positive")
        let child = try Spawner.spawn(request, connectsStandardInput: false)
        registry?.insert(child.pid)
        defer { registry?.remove(child.pid) }

        let execution = CollectingExecution(child: child, outputLimit: maximumOutputBytes)
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                execution.start(continuation: continuation, timeout: timeout)
            }
        } onCancel: {
            execution.cancel()
        }
        return try outcome.get()
    }
}

/// Collects a child's output and exit status. All mutable state lives behind one lock,
/// and the continuation is resumed exactly once.
private final class CollectingExecution: Sendable {
    private struct State {
        var output = Data()
        var errors = Data()
        var openStreams = 2
        var exit: ProcessExit?
        var failure: ProcessRunError?
        var continuation: CheckedContinuation<Result<ProcessResult, ProcessRunError>, Never>?
        var isFinished = false
    }

    private static let killGrace: DispatchTimeInterval = .seconds(2)
    private static let pipeGraceAfterExit: DispatchTimeInterval = .seconds(1)

    private let child: SpawnedChild
    private let outputLimit: Int
    private let queue = DispatchQueue(label: "codometer.process.collect", qos: .utility)
    private let state = Mutex(State())

    init(child: SpawnedChild, outputLimit: Int) {
        self.child = child
        self.outputLimit = outputLimit
    }

    func start(continuation: CheckedContinuation<Result<ProcessResult, ProcessRunError>, Never>, timeout: Duration) {
        state.withLock { $0.continuation = continuation }
        read(descriptor: child.standardOutput, isStandardOutput: true)
        read(descriptor: child.standardError, isStandardOutput: false)

        let pid = child.pid
        DispatchQueue.global(qos: .utility).async { [self] in
            let exit = Spawner.waitForExit(of: pid)
            recordExit(exit)
        }
        queue.asyncAfter(deadline: .now() + timeout.dispatchInterval) { [self] in
            fail(with: .timedOut(seconds: timeout.timeInterval))
        }
    }

    func cancel() {
        fail(with: .cancelled)
    }

    private func read(descriptor: Int32, isStandardOutput: Bool) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self, source] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    append(Data(buffer.prefix(count)), isStandardOutput: isStandardOutput)
                    continue
                }
                if count < 0 && errno == EINTR { continue }
                if count < 0 && errno == EAGAIN { return }
                source.cancel()
                return
            }
        }
        source.setCancelHandler { [self] in
            close(descriptor)
            streamClosed()
        }
        source.resume()
    }

    private func append(_ data: Data, isStandardOutput: Bool) {
        let exceeded = state.withLock { state -> Bool in
            if isStandardOutput {
                state.output.append(data)
            } else if state.errors.count < outputLimit {
                state.errors.append(data.prefix(outputLimit - state.errors.count))
            }
            return state.output.count > outputLimit
        }
        if exceeded {
            fail(with: .outputTooLarge(limit: outputLimit))
        }
    }

    private func streamClosed() {
        state.withLock { $0.openStreams -= 1 }
        finishIfComplete()
    }

    private func recordExit(_ exit: ProcessExit) {
        state.withLock { $0.exit = exit }
        finishIfComplete()
        // A grandchild may keep the pipes open after the child exits; do not wait for it forever.
        queue.asyncAfter(deadline: .now() + Self.pipeGraceAfterExit) { [self] in
            let stillOpen = state.withLock { !$0.isFinished && $0.openStreams > 0 }
            if stillOpen {
                Spawner.signalGroup(of: child.pid, SIGKILL)
                resume()
            }
        }
    }

    private func fail(with error: ProcessRunError) {
        let shouldKill = state.withLock { state -> Bool in
            guard !state.isFinished, state.failure == nil else { return false }
            state.failure = error
            return true
        }
        guard shouldKill else { return }
        Spawner.signalGroup(of: child.pid, SIGTERM)
        queue.asyncAfter(deadline: .now() + Self.killGrace) { [self] in
            Spawner.signalGroup(of: child.pid, SIGKILL)
            // If the process is unkillable, report the failure anyway rather than hanging the caller.
            queue.asyncAfter(deadline: .now() + Self.killGrace) { [self] in
                resume()
            }
        }
        finishIfComplete()
    }

    private func finishIfComplete() {
        let complete = state.withLock { $0.exit != nil && $0.openStreams == 0 }
        if complete { resume() }
    }

    private func resume() {
        let delivery = state.withLock { state -> (CheckedContinuation<Result<ProcessResult, ProcessRunError>, Never>, Result<ProcessResult, ProcessRunError>)? in
            guard !state.isFinished, let continuation = state.continuation else { return nil }
            state.isFinished = true
            state.continuation = nil
            if let failure = state.failure {
                return (continuation, .failure(failure))
            }
            let result = ProcessResult(
                processID: child.pid,
                exit: state.exit ?? .signaled(signal: SIGKILL),
                standardOutput: state.output,
                standardError: state.errors
            )
            return (continuation, .success(result))
        }
        guard let (continuation, result) = delivery else { return }
        continuation.resume(returning: result)
    }
}
