import Darwin
import Dispatch
import Foundation
import Synchronization

/// A long-running child process spoken to with newline-delimited messages over stdio.
public final class LineChannel: Sendable {
    public let processID: Int32
    /// Complete stdout lines. Finishes when the process closes stdout or is terminated.
    public let lines: AsyncStream<Data>

    private struct State {
        var pendingLine = Data()
        var discardingOversizedLine = false
        var isTerminated = false
    }

    private let standardInput: Int32
    private let maximumLineBytes: Int
    private let continuation: AsyncStream<Data>.Continuation
    private let registry: ChildProcessRegistry?
    private let queue = DispatchQueue(label: "codometer.linechannel", qos: .utility)
    private let state = Mutex(State())

    private init(
        child: SpawnedChild,
        maximumLineBytes: Int,
        registry: ChildProcessRegistry?
    ) {
        processID = child.pid
        standardInput = child.standardInput ?? -1
        self.maximumLineBytes = maximumLineBytes
        self.registry = registry
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(256))
        lines = stream
        self.continuation = continuation
    }

    public static func launch(
        _ request: ProcessRequest,
        maximumLineBytes: Int,
        registry: ChildProcessRegistry?
    ) throws(ProcessRunError) -> LineChannel {
        precondition(maximumLineBytes > 0, "line cap must be positive")
        let child = try Spawner.spawn(request, connectsStandardInput: true)
        registry?.insert(child.pid)
        let channel = LineChannel(child: child, maximumLineBytes: maximumLineBytes, registry: registry)
        channel.startReading(child: child)
        return channel
    }

    /// Writes one message followed by a newline.
    public func send(_ message: Data) throws(ProcessRunError) {
        guard !message.contains(UInt8(ascii: "\n")) else {
            throw .invalidRequest(reason: "a message must not contain newlines")
        }
        let terminated = state.withLock { $0.isTerminated }
        guard !terminated else { throw .cancelled }
        var payload = message
        payload.append(UInt8(ascii: "\n"))
        let failure: Int32? = payload.withUnsafeBytes { raw -> Int32? in
            var offset = 0
            while offset < raw.count {
                let written = write(standardInput, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                offset += written
            }
            return nil
        }
        if let failure {
            throw .pipeFailed(code: failure)
        }
    }

    /// Closes stdin and stops the process group; escalates to SIGKILL after a short grace period.
    public func terminate() {
        let alreadyTerminated = state.withLock { state -> Bool in
            defer { state.isTerminated = true }
            return state.isTerminated
        }
        guard !alreadyTerminated else { return }
        close(standardInput)
        Spawner.signalGroup(of: processID, SIGTERM)
        let pid = processID
        queue.asyncAfter(deadline: .now() + .seconds(1)) {
            Spawner.signalGroup(of: pid, SIGKILL)
        }
        continuation.finish()
    }

    private func startReading(child: SpawnedChild) {
        observe(descriptor: child.standardOutput) { [self] data in
            consumeOutput(data)
        } onClose: { [self] in
            continuation.finish()
        }
        // stderr is drained and discarded so a chatty child cannot block on a full pipe.
        observe(descriptor: child.standardError, onData: { _ in }, onClose: {})

        let pid = child.pid
        DispatchQueue.global(qos: .utility).async { [self] in
            _ = Spawner.waitForExit(of: pid)
            registry?.remove(pid)
            let wasTerminated = state.withLock { state -> Bool in
                defer { state.isTerminated = true }
                return state.isTerminated
            }
            if !wasTerminated {
                close(standardInput)
            }
            continuation.finish()
        }
    }

    private func observe(
        descriptor: Int32,
        onData: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [source] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    onData(Data(buffer.prefix(count)))
                    continue
                }
                if count < 0 && errno == EINTR { continue }
                if count < 0 && errno == EAGAIN { return }
                source.cancel()
                return
            }
        }
        source.setCancelHandler {
            close(descriptor)
            onClose()
        }
        source.resume()
    }

    private func consumeOutput(_ data: Data) {
        let completed = state.withLock { state -> [Data] in
            var lines: [Data] = []
            for byte in data {
                if byte == UInt8(ascii: "\n") {
                    if !state.discardingOversizedLine && !state.pendingLine.isEmpty {
                        lines.append(state.pendingLine)
                    }
                    state.pendingLine.removeAll(keepingCapacity: true)
                    state.discardingOversizedLine = false
                } else if !state.discardingOversizedLine {
                    state.pendingLine.append(byte)
                    if state.pendingLine.count > maximumLineBytes {
                        state.pendingLine.removeAll()
                        state.discardingOversizedLine = true
                    }
                }
            }
            return lines
        }
        for line in completed {
            continuation.yield(line)
        }
    }
}
