import CoreServices
import Dispatch
import Foundation

/// File-system change notifications for directory trees, backed by FSEvents.
///
/// The kernel coalesces events for `latency` seconds, so a busy log that is appended
/// hundreds of times per second still wakes the app about once per `latency`.
public enum DirectoryEvents {
    /// Yields batches of changed paths under `directories` until the stream is cancelled.
    public static func changes(in directories: [URL], latency: TimeInterval) -> AsyncStream<Set<String>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            let paths = directories.map(\.path)
            guard !paths.isEmpty else {
                continuation.finish()
                return
            }
            let sink = EventSink(continuation: continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(sink).toOpaque(),
                retain: nil,
                release: { info in
                    guard let info else { return }
                    Unmanaged<EventSink>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
                guard let info else { return }
                let sink = Unmanaged<EventSink>.fromOpaque(info).takeUnretainedValue()
                let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
                let changed = array.prefix(count).compactMap { $0 as? String }
                if !changed.isEmpty {
                    sink.continuation.yield(Set(changed))
                }
            }
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot
            )
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else {
                continuation.finish()
                return
            }
            let queue = DispatchQueue(label: "codometer.fsevents", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                continuation.finish()
                return
            }
            let handle = StreamHandle(stream: stream, queue: queue)
            continuation.onTermination = { _ in handle.stop() }
        }
    }
}

private final class EventSink: Sendable {
    let continuation: AsyncStream<Set<String>>.Continuation

    init(continuation: AsyncStream<Set<String>>.Continuation) {
        self.continuation = continuation
    }
}

/// Owns an FSEventStream. After `start`, the stream is only touched on its private serial queue.
private final class StreamHandle: @unchecked Sendable {
    private let stream: FSEventStreamRef
    private let queue: DispatchQueue

    init(stream: FSEventStreamRef, queue: DispatchQueue) {
        self.stream = stream
        self.queue = queue
    }

    func stop() {
        queue.async { [self] in
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
