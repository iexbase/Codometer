import CodometerCore
import Foundation
import Testing

private let account = AccountID()

private func point(_ minutes: Double, _ used: Double) throws -> UsagePoint {
    try UsagePoint(at: Fixture.now.addingTimeInterval(minutes * 60), used: used)
}

private func series(_ points: [UsagePoint], resets: [Double] = []) -> HistorySeries {
    HistorySeries(
        accountID: account,
        bucketID: "main",
        windowID: "session",
        points: points,
        resets: resets.map { Fixture.now.addingTimeInterval($0 * 60) }
    )
}

/// An interval from `from` to `to` minutes after `Fixture.now`.
private func interval(_ from: Double, _ to: Double) -> DateInterval {
    DateInterval(start: Fixture.now.addingTimeInterval(from * 60), end: Fixture.now.addingTimeInterval(to * 60))
}

private func sample(
    _ sessionID: String,
    project: String? = "/Users/me/Codometer",
    at minutes: Double = 10,
    input: Int64 = 0,
    output: Int64 = 0
) throws -> TokenSample {
    try TokenSample(
        accountID: account,
        sessionID: sessionID,
        project: project,
        model: "claude-fable-5",
        at: Fixture.now.addingTimeInterval(minutes * 60),
        delta: try Fixture.tokens(input: input, output: output)
    )
}

@Suite("History value types")
struct HistoryValueTests {
    @Test("Usage points must be finite and within the percentage sanity bound")
    func usagePoint() throws {
        #expect(try UsagePoint(at: Fixture.now, used: 130).used == 130)
        #expect(throws: ValidationError.notFinite(field: "usage.used")) { try UsagePoint(at: Fixture.now, used: .nan) }
        #expect(throws: ValidationError.self) { try UsagePoint(at: Fixture.now, used: -0.5) }
        #expect(throws: ValidationError.self) { try UsagePoint(at: Fixture.now, used: 1_001) }
    }

    @Test("A series keeps points and resets in ascending order")
    func seriesOrder() throws {
        let unordered = series([try point(10, 30), try point(0, 10), try point(5, 20)], resets: [9, 1])
        #expect(unordered.points.map(\.used) == [10, 20, 30])
        #expect(unordered.resets == [Fixture.now.addingTimeInterval(60), Fixture.now.addingTimeInterval(540)])
        #expect(!unordered.isEmpty)
        #expect(series([]).isEmpty)
    }

    @Test("Segments record only working and waiting time, never ending before they start")
    func segments() throws {
        let segment = try SessionSegment(
            accountID: account,
            sessionID: "s-1",
            title: nil,
            project: "/Users/me/exchanger-api\n",
            activity: .working,
            start: Fixture.now,
            end: nil
        )
        #expect(segment.title == "exchanger-api")
        #expect(segment.project == "/Users/me/exchanger-api")
        #expect(segment.isOpen)
        #expect(segment.duration(now: Fixture.now.addingTimeInterval(90)) == 90)
        #expect(segment.id == "\(account)/s-1/working/\(Int64(Fixture.now.timeIntervalSince1970 * 1_000))")

        let closed = try SessionSegment(
            accountID: account, sessionID: "s-1", title: "Title", project: nil, activity: .waiting,
            start: Fixture.now, end: Fixture.now.addingTimeInterval(30)
        )
        #expect(closed.title == "Title")
        #expect(closed.duration(now: Fixture.now.addingTimeInterval(9_999)) == 30)
        #expect(closed.id != segment.id)

        #expect(throws: ValidationError.self) {
            try SessionSegment(accountID: account, sessionID: "s", title: nil, project: nil, activity: .idle, start: Fixture.now, end: nil)
        }
        #expect(throws: ValidationError.self) {
            try SessionSegment(
                accountID: account, sessionID: "s", title: nil, project: nil, activity: .working,
                start: Fixture.now, end: Fixture.now.addingTimeInterval(-1)
            )
        }
        #expect(throws: ValidationError.invalidCharacters(field: "segment.sessionID")) {
            try SessionSegment(accountID: account, sessionID: " s", title: nil, project: nil, activity: .working, start: Fixture.now, end: nil)
        }
        #expect(try SessionSegment(
            accountID: account, sessionID: "s", title: nil, project: nil, activity: .working, start: Fixture.now, end: nil
        ).title == "—")
    }

    @Test("Timeline snapshots order segments by start")
    func timeline() throws {
        let later = try SessionSegment(
            accountID: account, sessionID: "b", title: "b", project: nil, activity: .working,
            start: Fixture.now.addingTimeInterval(60), end: nil
        )
        let earlier = try SessionSegment(
            accountID: account, sessionID: "a", title: "a", project: nil, activity: .waiting,
            start: Fixture.now, end: Fixture.now.addingTimeInterval(30)
        )
        let snapshot = TimelineSnapshot(accountID: account, interval: interval(0, 300), segments: [later, earlier], usage: nil)
        #expect(snapshot.segments.map(\.sessionID) == ["a", "b"])
        #expect(snapshot.coverageStart == nil)
        let covered = TimelineSnapshot(
            accountID: account, interval: interval(0, 300), segments: [], usage: nil, coverageStart: Fixture.now
        )
        #expect(covered.coverageStart == Fixture.now)
    }

    @Test("Token samples validate the session id and sanitise text")
    func tokenSample() throws {
        let sample = try TokenSample(
            accountID: account,
            sessionID: "019a-uuid",
            project: " /Users/me/Codometer ",
            model: String(repeating: "m", count: 90),
            at: Fixture.now,
            delta: .zero
        )
        #expect(sample.project == "/Users/me/Codometer")
        #expect(sample.model?.count == 60)
        #expect(throws: ValidationError.invalidCharacters(field: "tokens.sessionID")) {
            try TokenSample(accountID: account, sessionID: "", project: nil, model: nil, at: Fixture.now, delta: .zero)
        }
    }

    @Test("Attribution shares validate their numbers")
    func share() throws {
        let share = try AttributionShare(id: "project:x", subject: .project("x"), weightedTokens: 10, share: 0.25, estimatedPoints: 3.2)
        #expect(share.estimatedPoints == 3.2)
        #expect(share.subject == .project("x"))
        // A project name that sanitises to nothing counts as no project.
        let blank = try AttributionShare(id: "project:", subject: .project("\u{0}\n"), weightedTokens: 1, share: 1, estimatedPoints: nil)
        #expect(blank.subject == .noProject)
        #expect(throws: ValidationError.self) { try AttributionShare(id: "", subject: .project("x"), weightedTokens: 1, share: 0.5, estimatedPoints: nil) }
        #expect(throws: ValidationError.self) { try AttributionShare(id: "a", subject: .project("x"), weightedTokens: -1, share: 0.5, estimatedPoints: nil) }
        #expect(throws: ValidationError.self) { try AttributionShare(id: "a", subject: .project("x"), weightedTokens: 1, share: 1.01, estimatedPoints: nil) }
        #expect(throws: ValidationError.self) { try AttributionShare(id: "a", subject: .project("x"), weightedTokens: 1, share: .nan, estimatedPoints: nil) }
        #expect(throws: ValidationError.self) { try AttributionShare(id: "a", subject: .project("x"), weightedTokens: 1, share: 0.5, estimatedPoints: -2) }
        #expect(throws: ValidationError.self) { try AttributionShare(id: "a", subject: .project("x"), weightedTokens: .infinity, share: 0.5, estimatedPoints: nil) }
    }
}

@Suite("Consumed points")
struct ConsumedPointsTests {
    @Test("Positive deltas add up; small drops are noise")
    func positiveDeltas() throws {
        let usage = series([try point(0, 10), try point(5, 14), try point(10, 13), try point(15, 20)])
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 15)) == 11)
    }

    @Test("A drop of 20 points or more starts a new period")
    func largeDrop() throws {
        let usage = series([try point(0, 90), try point(5, 97), try point(10, 3), try point(15, 8)])
        // 90→97: 7; 97→3: new period, 3; 3→8: 5.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 15)) == 15)
        let exactlyTwenty = series([try point(0, 30), try point(5, 10)])
        #expect(UsageAttribution.consumedPoints(in: exactlyTwenty, interval: interval(0, 5)) == 10)
    }

    @Test("A reset marker between two observations starts a new period even without a large drop")
    func resetMarker() throws {
        let usage = series([try point(0, 12), try point(5, 15), try point(10, 4), try point(15, 6)], resets: [7])
        // 12→15: 3; reset at 7 min → 4 counts whole; 4→6: 2.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 15)) == 9)
        // A usage rise across a reset counts from zero, not from the old value.
        let rising = series([try point(0, 2), try point(10, 5)], resets: [5])
        #expect(UsageAttribution.consumedPoints(in: rising, interval: interval(0, 10)) == 5)
        // A marker exactly on the later observation still separates the two.
        let onPoint = series([try point(0, 2), try point(10, 5)], resets: [10])
        #expect(UsageAttribution.consumedPoints(in: onPoint, interval: interval(0, 10)) == 5)
        // Markers outside the pair do not affect it.
        let elsewhere = series([try point(0, 2), try point(10, 5)], resets: [-5, 0, 20])
        #expect(UsageAttribution.consumedPoints(in: elsewhere, interval: interval(0, 10)) == 3)
    }

    @Test("Only observations inside the interval count")
    func insideIntervalOnly() throws {
        let usage = series([try point(-10, 0), try point(0, 10), try point(5, 30), try point(20, 90)])
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 10)) == 20)
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(1, 10)) == 0)
        #expect(UsageAttribution.consumedPoints(in: series([]), interval: interval(0, 10)) == 0)
    }
}

@Suite("Consumed points over collection runs")
struct CollectionRunPointsTests {
    private func starts(_ minutes: [Double]) -> [Date] {
        minutes.map { Fixture.now.addingTimeInterval($0 * 60) }
    }

    @Test("Only pairs of observations inside one collection run count")
    func sameRunOnly() throws {
        let usage = series([try point(0, 10), try point(10, 20), try point(20, 35), try point(30, 40), try point(40, 50)])
        // 0→10: before the first run. 10→20: a run starts between. 20→30: counts 5. 30→40: a run starts between.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 40), collectionStarts: starts([32, 15])) == 5)
        // Without runs, or with runs only after the observations, nothing is estimated rather than zero.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 40), collectionStarts: []) == nil)
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 40), collectionStarts: starts([45])) == nil)
        // One run covering everything counts every pair, like the plain sum.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 40), collectionStarts: starts([-60])) == 40)
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 40)) == 40)
    }

    @Test("A run starting exactly at an observation owns it")
    func startOnObservation() throws {
        let usage = series([try point(0, 10), try point(10, 12), try point(20, 15)])
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 20), collectionStarts: starts([0])) == 5)
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 20), collectionStarts: starts([0, 10])) == 3)
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 20), collectionStarts: starts([0, 20])) == 2)
    }

    @Test("Resets inside a run still count from zero, and resets in skipped pairs are consumed in order")
    func resetsWithRuns() throws {
        let usage = series(
            [try point(0, 80), try point(10, 90), try point(20, 5), try point(30, 9), try point(40, 3), try point(50, 6)],
            resets: [15, 35]
        )
        // 0→10 skipped (run starts at 5); 10→20 reset: 5; 20→30: 4; 30→40 skipped (run at 32, reset at 35); 40→50: 3.
        #expect(UsageAttribution.consumedPoints(in: usage, interval: interval(0, 50), collectionStarts: starts([5, 32])) == 12)
    }
}

@Suite("Session labels")
struct SessionLabelTests {
    @Test("The folder is the sanitised last path component")
    func folder() {
        #expect(SessionLabel.folder(of: nil) == nil)
        #expect(SessionLabel.folder(of: "") == nil)
        #expect(SessionLabel.folder(of: "/") == nil)
        #expect(SessionLabel.folder(of: "/Users/me/Codometer") == "Codometer")
        #expect(SessionLabel.folder(of: "/Users/me/Мой проект/") == "Мой проект")
        #expect(SessionLabel.folder(of: "Codometer") == "Codometer")
        #expect(SessionLabel.folder(of: "/tmp/a\u{0}b\n") == "ab")
        let long = "/Users/me/" + String(repeating: "x", count: 300)
        #expect(SessionLabel.folder(of: long) == String(repeating: "x", count: SessionLabel.maximumFolderLength - 1) + "…")
    }

    @Test("Labels use the folder and the end of the id, never a title; the stored form has no words")
    func labels() {
        #expect(SessionLabel.neutral(sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d", project: "/Users/me/Codometer") == "Codometer · e70d2d")
        #expect(SessionLabel.neutral(sessionID: "abc", project: nil) == "abc")
        let parts = SessionLabel.parts(sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d", projectFolder: "/Users/me/Codometer")
        #expect(parts == SessionLabelParts(folder: "Codometer", idSuffix: "e70d2d"))
        #expect(SessionLabel.parts(sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d", projectFolder: "Codometer") == parts)
        #expect(SessionLabel.parts(sessionID: "4ecca291-a70a-4fe9-9306-426595e70d2d", projectFolder: "/") == SessionLabelParts(folder: nil, idSuffix: "e70d2d"))
        #expect(SessionLabelParts(folder: nil, idSuffix: "e70d2d").machineForm == "e70d2d")
    }
}

@Suite("Usage attribution")
struct UsageAttributionTests {
    @Test("Points count only while tokens were collected, not the usage before the first collection start")
    func pointsFromCollectionOnly() throws {
        // The window climbed to 39 % before the app started collecting at minute 0, then gained 2 points.
        let usage = series([try point(-240, 0), try point(-120, 20), try point(-10, 39), try point(5, 40), try point(30, 41)])
        let samples = [try sample("a", at: 10, input: 300), try sample("b", project: "/p/other", at: 20, input: 100)]
        let started = [Fixture.now]
        let report = UsageAttribution.report(
            samples: samples, provider: .claude, usage: usage, interval: interval(-300, 60), grouping: .project, reference: nil,
            collectionStarts: started
        )
        #expect(report.usedPoints == 1)
        #expect(report.shares.compactMap(\.estimatedPoints) == [0.75, 0.25])

        // A restart between two observations drops that pair: usage while the app was quit has no tokens.
        let restarted = UsageAttribution.report(
            samples: samples, provider: .claude, usage: usage, interval: interval(-300, 60), grouping: .project, reference: nil,
            collectionStarts: started + [Fixture.now.addingTimeInterval(20 * 60)]
        )
        #expect(restarted.usedPoints == nil)
        #expect(restarted.shares.allSatisfy { $0.estimatedPoints == nil })
        #expect(restarted.shares.map(\.share) == [0.75, 0.25])

        // Callers that know no runs keep the plain estimate.
        let unknown = UsageAttribution.report(
            samples: samples, provider: .claude, usage: usage, interval: interval(-300, 60), grouping: .project, reference: nil
        )
        #expect(unknown.usedPoints == 41)
    }

    @Test("No samples or zero tokens produce an empty report that still knows the window's usage")
    func empty() throws {
        let usage = series([try point(0, 10), try point(10, 25)])
        let reference = try Fixture.window("session", .session, used: 25)
        let none = UsageAttribution.report(
            samples: [], provider: .claude, usage: usage, interval: interval(0, 10), grouping: .project, reference: reference
        )
        #expect(none.shares.isEmpty)
        #expect(none.isEmpty)
        #expect(none.totalWeightedTokens == 0)
        #expect(none.usedPoints == 15)
        #expect(none.windowTitleSource == reference)
        #expect(none.interval == interval(0, 10))
        #expect(none.coverageStart == nil)

        let zero = UsageAttribution.report(
            samples: [try sample("a"), try sample("b", project: nil)],
            provider: .codex, usage: nil, interval: interval(0, 60), grouping: .session, reference: nil
        )
        #expect(zero.shares.isEmpty)
        #expect(zero.totalWeightedTokens == 0)
        #expect(zero.usedPoints == nil)
    }

    @Test("Project shares are weighted, sorted and converted to window points")
    func projects() throws {
        let samples = [
            try sample("a", project: "/Users/me/Codometer", at: 5, input: 1_000),
            try sample("b", project: "/Users/me/Codometer", at: 20, output: 200),
            try sample("c", project: "/Users/me/exchanger-api", at: 30, input: 6_000),
            try sample("d", project: nil, at: 40, output: 400),
            // Outside the interval: ignored.
            try sample("e", project: "/Users/me/old", at: 90, input: 1_000_000),
            try sample("f", project: "/Users/me/old", at: -1, input: 1_000_000),
        ]
        let usage = series([try point(0, 10), try point(30, 20), try point(60, 30), try point(70, 90)])
        let report = UsageAttribution.report(
            samples: samples, provider: .claude, usage: usage, interval: interval(0, 60), grouping: .project, reference: nil
        )
        // Claude: Codometer 1000 + 200×5 = 2000; exchanger-api 6000; no project 400×5 = 2000.
        #expect(report.totalWeightedTokens == 10_000)
        #expect(report.usedPoints == 20)
        #expect(report.shares.map(\.subject) == [.project("exchanger-api"), .project("Codometer"), .noProject])
        #expect(report.shares.map(\.id) == ["project:/Users/me/exchanger-api", "project:/Users/me/Codometer", "project:"])
        #expect(report.shares.map(\.weightedTokens) == [6_000, 2_000, 2_000])
        #expect(report.shares.map(\.share) == [0.6, 0.2, 0.2])
        let points = report.shares.compactMap(\.estimatedPoints)
        #expect(points.count == 3)
        #expect(zip(points, [12.0, 4.0, 4.0]).allSatisfy { abs($0 - $1) < 1e-9 })
        // The earliest sample inside the interval, not the older one outside it.
        #expect(report.coverageStart == Fixture.now.addingTimeInterval(5 * 60))
    }

    @Test("Session shares are titled by project and id suffix")
    func sessions() throws {
        let samples = [
            try sample("11111111-aaaa-bbbb-cccc-000000abcdef", project: nil, at: 1, output: 10),
            try sample("11111111-aaaa-bbbb-cccc-000000abcdef", project: "/Users/me/Codometer", at: 2, output: 10),
            try sample("22222222-aaaa-bbbb-cccc-000000123456", project: nil, at: 3, input: 30),
        ]
        let report = UsageAttribution.report(
            samples: samples, provider: .codex, usage: nil, interval: interval(0, 10), grouping: .session, reference: nil
        )
        #expect(report.shares.map(\.subject) == [
            .session(SessionLabelParts(folder: "Codometer", idSuffix: "abcdef")),
            .session(SessionLabelParts(folder: nil, idSuffix: "123456")),
        ])
        #expect(report.shares.map(\.id) == ["session:11111111-aaaa-bbbb-cccc-000000abcdef", "session:22222222-aaaa-bbbb-cccc-000000123456"])
        #expect(report.shares.allSatisfy { $0.estimatedPoints == nil })
        #expect(report.usedPoints == nil)
    }

    @Test("More than eight groups fold the smallest into «другое»")
    func folding() throws {
        let samples = try (1...11).map { index in
            try sample("s\(index)", project: "/p/project-\(index)", input: Int64(index * 100))
        }
        let usage = series([try point(0, 0), try point(60, 50)])
        let report = UsageAttribution.report(
            samples: samples, provider: .claude, usage: usage, interval: interval(0, 60), grouping: .project, reference: nil
        )
        #expect(report.shares.count == 9)
        #expect(report.shares.prefix(8).map(\.subject) == (4...11).reversed().map { AttributionSubject.project("project-\($0)") })
        let other = try #require(report.shares.last)
        #expect(other.id == UsageAttribution.otherShareID)
        #expect(other.subject == .other)
        #expect(other.weightedTokens == 600)
        #expect(report.totalWeightedTokens == 6_600)
        #expect(abs(report.shares.map(\.share).reduce(0, +) - 1) < 1e-9)
        #expect(abs((other.estimatedPoints ?? 0) - 50 * 600 / 6_600) < 1e-9)

        let exactlyEight = UsageAttribution.report(
            samples: Array(samples.prefix(8)), provider: .claude, usage: nil, interval: interval(0, 60), grouping: .project, reference: nil
        )
        #expect(exactlyEight.shares.count == 8)
        #expect(!exactlyEight.shares.contains { $0.id == UsageAttribution.otherShareID })
    }

    @Test("Equal weights are ordered by name for a stable list")
    func ties() throws {
        let samples = [
            try sample("b", project: "/p/beta", input: 100),
            try sample("a", project: "/p/alpha", input: 100),
        ]
        let report = UsageAttribution.report(
            samples: samples, provider: .codex, usage: nil, interval: interval(0, 60), grouping: .project, reference: nil
        )
        #expect(report.shares.map(\.subject) == [.project("alpha"), .project("beta")])
    }

    @Test("Usage known but too sparse in the interval leaves points unestimated")
    func sparseUsage() throws {
        let usage = series([try point(-30, 10), try point(5, 20), try point(90, 40)])
        let report = UsageAttribution.report(
            samples: [try sample("a", input: 10)], provider: .claude, usage: usage, interval: interval(0, 60), grouping: .project, reference: nil
        )
        #expect(report.usedPoints == nil)
        #expect(report.shares.count == 1)
        #expect(report.shares[0].share == 1)
        #expect(report.shares[0].estimatedPoints == nil)
    }

    @Test("A reset inside the interval does not make usage negative")
    func resetInsideInterval() throws {
        let usage = series([try point(0, 80), try point(20, 95), try point(40, 2), try point(60, 12)], resets: [30])
        let report = UsageAttribution.report(
            samples: [try sample("a", input: 50), try sample("b", project: "/p/other", input: 50)],
            provider: .codex, usage: usage, interval: interval(0, 60), grouping: .project, reference: nil
        )
        #expect(report.usedPoints == 27)
        #expect(report.shares.compactMap(\.estimatedPoints) == [13.5, 13.5])
    }
}
