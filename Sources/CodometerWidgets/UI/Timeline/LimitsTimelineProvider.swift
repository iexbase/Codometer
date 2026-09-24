import CodometerCore
import CodometerL10n
import Foundation
import WidgetKit

/// One moment of a widget: its scope's part of the snapshot as it stands at `date`.
public struct LimitsEntry: TimelineEntry, Sendable {
    public let date: Date
    /// Already scoped to `scope`. `nil` shows "No data"; a snapshot without accounts shows the scope's empty state.
    public let snapshot: WidgetSnapshot?
    public let scope: WidgetScope
    /// The snapshot's language, or the system's while there is no snapshot.
    public let localizer: Localizer

    public init(date: Date, snapshot: WidgetSnapshot?, scope: WidgetScope = .all) {
        self.date = date
        self.snapshot = snapshot
        self.scope = scope
        localizer = Localizer(language: snapshot?.language ?? Language.resolve(.system))
    }

    /// Accounts projected to the entry's date.
    public var states: [WidgetAccountState] {
        snapshot?.states(at: date) ?? []
    }

    /// The worst band across accounts with fresh numbers, for the background glow.
    public var urgency: UsageBand? {
        states.filter { !$0.isStale }.compactMap(\.worstBand).max()
    }

    public var hasAttention: Bool {
        (snapshot?.attentionCount ?? 0) > 0
    }
}

/// Reads the app's snapshot and lays out entries for now, every upcoming reset, the hour before each reset (where
/// the countdown switches to minutes) and every moment data turns stale — for one widget scope.
///
/// The extension does no work between entries: countdowns are live system text, and the app asks WidgetKit to
/// reload when it publishes a new snapshot. An hourly reload picks up a snapshot whose reload request was dropped by
/// the system's budget. Every request writes one line of diagnostics (`WidgetDiagnostics`).
public struct LimitsTimelineProvider: TimelineProvider {
    /// A fallback only: every reload spends the widget's daily budget, and the app already reloads the widget when it
    /// publishes new numbers.
    public static let refreshInterval: TimeInterval = 60 * 60

    public let scope: WidgetScope
    /// The layout this widget always uses (the strip widgets), or `nil` to follow the app's widget layout setting.
    public let layout: WidgetLayout?
    private let read: @Sendable () -> SnapshotReadResult

    public init(
        scope: WidgetScope = .all,
        layout: WidgetLayout? = nil,
        read: @escaping @Sendable () -> SnapshotReadResult = { SnapshotFileReader.standard()?.read() ?? .noHome }
    ) {
        self.scope = scope
        self.layout = layout
        self.read = read
    }

    private var kind: String {
        layout == .strip ? scope.stripKind : scope.kind
    }

    /// The snapshot in this widget's own layout, when it has one.
    private func laidOut(_ snapshot: WidgetSnapshot?) -> WidgetSnapshot? {
        guard let layout else { return snapshot }
        return snapshot?.laidOut(layout)
    }

    /// Must answer at once and without I/O: sample numbers, redacted by the system.
    public func placeholder(in context: Context) -> LimitsEntry {
        let now = Date()
        let sample = WidgetSampleData.snapshot(now: now, language: Language.resolve(.system), layout: layout ?? .rings)
        return LimitsEntry(date: now, snapshot: sample.scoped(to: scope), scope: scope)
    }

    /// The gallery shows the user's own numbers, or sample numbers while there are none for this scope.
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (LimitsEntry) -> Void) {
        let now = Date()
        let result = read()
        let entry = Self.previewEntry(for: laidOut(result.snapshot), scope: scope, isPreview: context.isPreview, now: now)
        WidgetDiagnostics.record(.snapshot, scope: scope, kind: kind, family: context.family, result: result, entries: 1, now: now)
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LimitsEntry>) -> Void) {
        let now = Date()
        let result = read()
        let entries = Self.entries(for: laidOut(result.snapshot), scope: scope, now: now)
        WidgetDiagnostics.record(.timeline, scope: scope, kind: kind, family: context.family, result: result, entries: entries.count, now: now)
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }

    static func entries(for snapshot: WidgetSnapshot?, scope: WidgetScope = .all, now: Date) -> [LimitsEntry] {
        guard let scoped = snapshot?.scoped(to: scope) else { return [LimitsEntry(date: now, snapshot: nil, scope: scope)] }
        return scoped.timelineDates(from: now).map { LimitsEntry(date: $0, snapshot: scoped, scope: scope) }
    }

    static func previewEntry(for snapshot: WidgetSnapshot?, scope: WidgetScope, isPreview: Bool, now: Date) -> LimitsEntry {
        var scoped = snapshot?.scoped(to: scope)
        if isPreview, scoped?.accounts.isEmpty ?? true {
            // Sample numbers in the app's language and layout when a snapshot says them, else the system's language.
            let language = snapshot?.language ?? Language.resolve(.system)
            scoped = WidgetSampleData.snapshot(now: now, language: language, layout: snapshot?.layout ?? .rings).scoped(to: scope)
        }
        return LimitsEntry(date: now, snapshot: scoped, scope: scope)
    }
}
