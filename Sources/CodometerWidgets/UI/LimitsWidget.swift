import CodometerCore
import CodometerL10n
import SwiftUI
import WidgetKit

/// "AI Limits": usage rings for every enabled account, the nearest reset and who is waiting.
public struct LimitsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        let gallery = WidgetGallery.text(for: .all, l10n: WidgetGallery.localizer)
        return StaticConfiguration(kind: WidgetScope.all.kind, provider: LimitsTimelineProvider(scope: .all)) { entry in
            LimitsWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: gallery.name))
        .description(Text(verbatim: gallery.description))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// "Claude": the most constrained Claude account, or up to three of them side by side.
public struct ClaudeLimitsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ProviderWidgetConfiguration.make(provider: .claude)
    }
}

/// "Codex": the most constrained Codex account, or up to three of them side by side.
public struct CodexLimitsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ProviderWidgetConfiguration.make(provider: .codex)
    }
}

/// The configuration both provider widgets share. Static on purpose: SwiftPM cannot build App Intents metadata, so
/// the provider is a widget kind of its own rather than an intent parameter.
@MainActor
enum ProviderWidgetConfiguration {
    static func make(provider: ProviderKind) -> some WidgetConfiguration {
        let scope = WidgetScope.provider(provider)
        let gallery = WidgetGallery.text(for: scope, l10n: WidgetGallery.localizer)
        return StaticConfiguration(kind: scope.kind, provider: LimitsTimelineProvider(scope: scope)) { entry in
            LimitsWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: gallery.name))
        .description(Text(verbatim: gallery.description))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// "AI Limits · Strip": every account, always as the wide strip.
public struct LimitsStripWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StripWidgetConfiguration.make(scope: .all)
    }
}

/// "Claude · Strip": the Claude accounts as the wide strip.
public struct ClaudeStripWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StripWidgetConfiguration.make(scope: .provider(.claude))
    }
}

/// "Codex · Strip": the Codex accounts as the wide strip.
public struct CodexStripWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StripWidgetConfiguration.make(scope: .provider(.codex))
    }
}

/// The strip widgets: their own kinds, so the strip can be picked straight from the widget gallery, next to the ring
/// widgets, for every account, Claude or Codex. Medium and large only: the strip needs the width.
@MainActor
enum StripWidgetConfiguration {
    static func make(scope: WidgetScope) -> some WidgetConfiguration {
        let gallery = WidgetGallery.stripText(for: scope, l10n: WidgetGallery.localizer)
        return StaticConfiguration(kind: scope.stripKind, provider: LimitsTimelineProvider(scope: scope, layout: .strip)) { entry in
            LimitsWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(verbatim: gallery.name))
        .description(Text(verbatim: gallery.description))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// The names and descriptions the widget gallery shows.
///
/// WidgetKit reads them once when the extension starts, so they are written in the language of the snapshot found at
/// that moment (the app's language), or in the system's language before the app has written one. After a language
/// change the gallery follows once the system restarts the extension; the widgets themselves follow at once.
enum WidgetGallery {
    /// Read once per extension process, through the same bounded, symlink-refusing reader as the timeline.
    static let localizer = Localizer(language: SnapshotFileReader.standard()?.load()?.language ?? Language.resolve(.system))

    static func text(for scope: WidgetScope, l10n: Localizer) -> (name: String, description: String) {
        switch scope {
        case .all:
            return (l10n.widget.allName, l10n.widget.allDescription)
        case .provider(let provider):
            let name = WidgetText.providerName(provider)
            return (name, l10n.widget.providerDescription(name))
        }
    }

    static func stripText(for scope: WidgetScope, l10n: Localizer) -> (name: String, description: String) {
        let base = switch scope {
        case .all: l10n.widget.allName
        case .provider(let provider): WidgetText.providerName(provider)
        }
        return (l10n.widget.stripName(base), l10n.widget.stripDescription)
    }
}
