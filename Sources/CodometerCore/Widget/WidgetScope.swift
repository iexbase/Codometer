import Foundation

/// Which accounts a desktop widget shows. Every scope is its own WidgetKit kind, so the user can place "AI Limits"
/// next to a small «Claude» and a small «Codex».
public enum WidgetScope: Hashable, Sendable, CaseIterable {
    /// "AI Limits": every enabled account.
    case all
    /// «Claude» or «Codex»: one provider's accounts only.
    case provider(ProviderKind)

    public static var allCases: [WidgetScope] {
        [.all] + ProviderKind.allCases.map { .provider($0) }
    }

    /// The WidgetKit kind. These strings identify widgets the user already placed: never rename them.
    public var kind: String {
        switch self {
        case .all: "CodometerLimits"
        case .provider(.claude): "CodometerClaude"
        case .provider(.codex): "CodometerCodex"
        }
    }

    /// The WidgetKit kind of the scope's strip widget, which always shows the strip whatever the app's widget layout.
    /// Never rename these either.
    public var stripKind: String {
        switch self {
        case .all: "CodometerStrip"
        case .provider(.claude): "CodometerClaudeStrip"
        case .provider(.codex): "CodometerCodexStrip"
        }
    }

    public init?(kind: String) {
        guard let scope = Self.allCases.first(where: { $0.kind == kind }) else { return nil }
        self = scope
    }

    public var provider: ProviderKind? {
        switch self {
        case .all: nil
        case .provider(let provider): provider
        }
    }
}

extension WidgetSnapshot {
    /// Every widget kind the extension declares, for reloading them together.
    public static var widgetKinds: [String] {
        WidgetScope.allCases.map(\.kind) + WidgetScope.allCases.map(\.stripKind)
    }

    /// The snapshot as one scope's widget sees it: only the scope's accounts, in settings order, with the waiting
    /// and working counts of those accounts alone.
    /// The same snapshot drawn in `layout`: the strip widgets use it to show the strip whatever the setting says.
    public func laidOut(_ layout: WidgetLayout) -> WidgetSnapshot {
        guard layout != self.layout else { return self }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            accounts: accounts,
            bands: bands,
            attentionCount: attentionCount,
            workingCount: workingCount,
            language: language,
            showsForecast: showsForecast,
            layout: layout
        )
    }

    public func scoped(to scope: WidgetScope) -> WidgetSnapshot {
        guard let provider = scope.provider else { return self }
        let kept = accounts.filter { $0.provider == provider }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            accounts: kept,
            bands: bands,
            attentionCount: kept.reduce(0) { $0 + $1.waitingCount },
            workingCount: kept.reduce(0) { $0 + $1.workingCount },
            language: language,
            showsForecast: showsForecast,
            layout: layout
        )
    }
}

extension WidgetSelection {
    /// The most constrained account of one provider, or `nil` when the provider has no account.
    public static func mostConstrained(_ states: [WidgetAccountState], provider: ProviderKind) -> WidgetAccountState? {
        mostConstrained(states.filter { $0.account.provider == provider })
    }
}

extension WidgetAccountState {
    /// The window for the inner ring beside `binding`: the busiest other main-bucket window, preferring one of a
    /// different length, so a session ring is paired with a weekly one and the other way round. Ties keep display
    /// order; `nil` when the main bucket has no second window.
    public var companion: WidgetWindowState? {
        guard let binding else { return nil }
        let others = windows.filter { $0.source.isMainBucket && $0.id != binding.id }
        let otherLength = others.filter { $0.window.duration != binding.window.duration }
        return Self.busiest(otherLength.isEmpty ? others : otherLength)
    }

    private static func busiest(_ windows: [WidgetWindowState]) -> WidgetWindowState? {
        var best: WidgetWindowState?
        for window in windows where best.map({ window.window.used > $0.window.used }) ?? true {
            best = window
        }
        return best
    }

    /// Whether any agent of the account is working and none waits: the widget shows a working badge only then,
    /// because waiting outranks it.
    public var isWorkingOnly: Bool {
        account.workingCount > 0 && account.waitingCount == 0
    }
}
