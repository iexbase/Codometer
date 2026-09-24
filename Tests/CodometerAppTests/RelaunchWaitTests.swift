@testable import CodometerApp
import Darwin
import Foundation
import Testing

/// What a launch does when the instance lock is busy: an ordinary second copy hands over at once, a relaunch waits
/// for the copy it replaced.
@Suite("Relaunch wait")
struct RelaunchWaitTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-relaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("--relaunched-after is read only when it names a plausible pid")
    func argumentParsing() {
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer"]) == nil)
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer", "--relaunched-after"]) == nil)
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer", "--relaunched-after", "0"]) == nil)
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer", "--relaunched-after", "-3"]) == nil)
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer", "--relaunched-after", "later"]) == nil)
        #expect(RelaunchArguments.predecessorPID(in: ["Codometer", "--relaunched-after", "4242"]) == 4242)
        #expect(RelaunchArguments.flag == "--relaunched-after")
    }

    @Test("Without the argument a busy lock is never waited for")
    func ordinarySecondCopyDoesNotWait() {
        var waited = false
        let result = InstanceGate.acquire(
            predecessor: nil,
            attempt: { .busy },
            waitForExit: { _, _ in
                waited = true
                return true
            }
        )
        #expect(result.outcome == .busy)
        #expect(result.lock == nil)
        #expect(!waited)
    }

    @Test("A relaunch takes the lock once the copy it replaced lets go")
    func relaunchAcquiresAfterPredecessorExits() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".lock", isDirectory: false)
        guard case .acquired(let predecessor) = InstanceLock.acquire(at: file) else {
            Issue.record("the predecessor could not take the lock")
            return
        }

        var timeoutSeen: TimeInterval?
        let result = InstanceGate.acquire(
            predecessor: 4242,
            attempt: { InstanceLock.acquire(at: file) },
            waitForExit: { _, timeout in
                timeoutSeen = timeout
                // The predecessor exits: its descriptor closes and the lock becomes free.
                predecessor.release()
                return true
            }
        )
        #expect(result.outcome == .acquired)
        #expect(timeoutSeen == InstanceGate.relaunchWait)
        result.lock?.release()
    }

    @Test("A predecessor that never exits leaves the new copy on the quit path")
    func relaunchQuitsWhenPredecessorStays() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".lock", isDirectory: false)
        guard case .acquired(let predecessor) = InstanceLock.acquire(at: file) else {
            Issue.record("the predecessor could not take the lock")
            return
        }
        defer { predecessor.release() }

        // The wait timed out.
        let timedOut = InstanceGate.acquire(
            predecessor: 4242,
            attempt: { InstanceLock.acquire(at: file) },
            waitForExit: { _, _ in false }
        )
        #expect(timedOut.outcome == .busy)

        // The wait said the process was gone, but the lock is still held (another copy took it meanwhile).
        let stillBusy = InstanceGate.acquire(
            predecessor: 4242,
            attempt: { InstanceLock.acquire(at: file) },
            waitForExit: { _, _ in true }
        )
        #expect(stillBusy.outcome == .busy)
        #expect(stillBusy.lock == nil)
    }

    @Test("A lock file that cannot be opened lets the launch go on without a lock")
    func unopenableLockDoesNotBlockLaunch() {
        let result = InstanceGate.acquire(
            predecessor: nil,
            attempt: { .unavailable(reason: "permission denied (13)") },
            waitForExit: { _, _ in true }
        )
        #expect(result.outcome == .unlocked(reason: "permission denied (13)"))
        #expect(result.lock == nil)
    }

    @Test("Waiting for a process that is already gone returns at once")
    func waitingForAGoneProcessReturns() {
        // pid 0 is never a process this waiter can see, and an unused high pid is treated as gone.
        #expect(InstanceGate.waitForProcessExit(999_999, timeout: 0.2))
    }
}
