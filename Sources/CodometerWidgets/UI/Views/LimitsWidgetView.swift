import CodometerCore
import CodometerL10n
import SwiftUI
import WidgetKit

/// The widget's root view inside WidgetKit: reads the family, rendering mode and colour scheme from the
/// environment and sets the container background.
public struct LimitsWidgetView: View {
    let entry: LimitsEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    public init(entry: LimitsEntry) {
        self.entry = entry
    }

    public var body: some View {
        let palette = WidgetPalette(style: WidgetStyle(renderingMode), scheme: colorScheme)
        LimitsWidgetContent(entry: entry, family: family, palette: palette)
            .containerBackground(for: .widget) {
                WidgetBackground(urgency: entry.urgency, hasAttention: entry.hasAttention, scheme: colorScheme)
            }
            .environment(\.widgetL10n, entry.localizer)
            .environment(\.locale, entry.localizer.locale)
    }
}

/// Everything inside the container, for an explicit family and palette so it can also be rendered outside WidgetKit.
public struct LimitsWidgetContent: View {
    let entry: LimitsEntry
    let family: WidgetFamily
    let palette: WidgetPalette

    public init(entry: LimitsEntry, family: WidgetFamily, palette: WidgetPalette) {
        self.entry = entry
        self.family = family
        self.palette = palette
    }

    public var body: some View {
        let states = entry.states
        if let provider = entry.scope.provider, let snapshot = entry.snapshot {
            ProviderLimitsContent(provider: provider, snapshot: snapshot, states: states, family: family, palette: palette)
        } else if let snapshot = entry.snapshot, let featured = WidgetSelection.mostConstrained(states) {
            switch family {
            case .systemSmall:
                SmallLimitsView(state: featured, attentionCount: snapshot.attentionCount, palette: palette)
            case _ where snapshot.layout == .strip:
                StripLimitsView(scope: .all, snapshot: snapshot, states: states, family: family, palette: palette)
            case .systemMedium:
                MediumLimitsView(states: WidgetSelection.featured(states, limit: 3), palette: palette)
            default:
                LargeLimitsView(snapshot: snapshot, states: states, palette: palette)
            }
        } else {
            EmptyLimitsView(isCompact: family == .systemSmall, palette: palette)
        }
    }
}

/// No snapshot yet, export turned off, or no enabled accounts.
struct EmptyLimitsView: View {
    @Environment(\.widgetL10n) private var l10n
    let isCompact: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .inset(by: 3)
                    .stroke(palette.track, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0.1, 6.5]))
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
            Text(verbatim: l10n.common.noData)
                .font(WidgetFont.text(14, .semibold))
                .foregroundStyle(palette.primary)
            Text(verbatim: isCompact ? l10n.widget.openApp : l10n.widget.openAppToSeeLimits)
                .font(WidgetFont.text(11.5, .medium))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
