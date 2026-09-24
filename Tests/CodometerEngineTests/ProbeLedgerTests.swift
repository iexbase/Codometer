import CodometerCore
@testable import CodometerEngine
import Foundation
import Testing

@Suite("Probe ledger")
struct ProbeLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_789_600_000)

    @Test("Keeps at most sixteen records, newest first")
    func ringBuffer() {
        var ledger = ProbeLedger(kind: .claudeUsageCommand)
        for index in 0..<40 {
            let at = start.addingTimeInterval(Double(index) * 60)
            ledger.begin(at: at)
            ledger.end(at: at.addingTimeInterval(2), outcome: .reading(windowCount: index))
        }
        #expect(ProbeLedger.capacity == AccountDiagnostics.maximumProbes)
        #expect(ledger.records.count == ProbeLedger.capacity)
        #expect(ledger.records.first?.outcome == .reading(windowCount: 39))
        #expect(ledger.records.last?.outcome == .reading(windowCount: 24))
        #expect(ledger.records.map(\.startedAt) == ledger.records.map(\.startedAt).sorted(by: >))
    }

    @Test("Pairs begin with end and measures the duration")
    func pairing() {
        var ledger = ProbeLedger(kind: .codexAppServer)
        #expect(!ledger.isRunning)
        ledger.begin(at: start)
        #expect(ledger.isRunning)
        #expect(ledger.records.isEmpty)
        ledger.end(at: start.addingTimeInterval(2.5), outcome: .reading(windowCount: 3))
        #expect(!ledger.isRunning)
        #expect(ledger.records.count == 1)
        #expect(ledger.records[0].kind == .codexAppServer)
        #expect(ledger.records[0].duration == 2.5)
    }

    @Test("A second begin without an end replaces the first attempt")
    func repeatedBegin() {
        var ledger = ProbeLedger(kind: .claudeUsageCommand)
        ledger.begin(at: start)
        ledger.begin(at: start.addingTimeInterval(10))
        ledger.end(at: start.addingTimeInterval(11), outcome: .failure(.timedOut))
        #expect(ledger.records.count == 1)
        #expect(ledger.records[0].duration == 1)
    }

    @Test("A skip needs no begin and never closes a running attempt")
    func skipWithoutBegin() {
        var ledger = ProbeLedger(kind: .codexAppServer)
        ledger.skip(.offline, at: start)
        #expect(ledger.records.count == 1)
        #expect(ledger.records[0].outcome == .skipped(.offline))
        #expect(ledger.records[0].duration == 0)
        #expect(!ledger.isRunning)

        ledger.begin(at: start.addingTimeInterval(60))
        ledger.skip(.logsFresh, at: start.addingTimeInterval(61))
        #expect(ledger.isRunning)
        ledger.end(at: start.addingTimeInterval(62), outcome: .reading(windowCount: 1))
        #expect(ledger.records.count == 3)
        #expect(ledger.records[0].outcome == .reading(windowCount: 1))
    }

    @Test("An end without a begin is recorded as instantaneous")
    func endWithoutBegin() {
        var ledger = ProbeLedger(kind: .claudeUsageCommand)
        ledger.end(at: start, outcome: .failure(.commandFailed))
        #expect(ledger.records.count == 1)
        #expect(ledger.records[0].duration == 0)
    }

    @Test("A clock set back never makes a negative duration")
    func clockMovedBack() {
        var ledger = ProbeLedger(kind: .claudeUsageCommand)
        ledger.begin(at: start)
        ledger.end(at: start.addingTimeInterval(-30), outcome: .reading(windowCount: 2))
        #expect(ledger.records[0].duration == 0)
        #expect(ledger.records[0].finishedAt == start)
    }
}
