import CodometerCore
import CodometerL10n
import SwiftUI

/// "What’s eating your limit": the projects or sessions that used the most of the limit over a period.
///
/// Ideally `120 × scale` points tall (never shorter) and as wide as offered, whatever the data, so loading never
/// resizes the deck: a header with the coverage note and four rows (title, share bar, "≈3.2%"), the rest folded into
/// "Other". Offered more height by its page, it keeps the rows' pitch and lists more of them
/// (`AttributionRows.slotCount`); the height still comes from the layout, never from the data.
public struct AttributionListView: View {
    let report: AttributionReport?
    let metrics: IslandMetrics

    @Environment(\.analyticsStyle) private var style
    @Environment(\.l10n) private var l10n

    public init(report: AttributionReport?, metrics: IslandMetrics) {
        self.report = report
        self.metrics = metrics
    }

    public static func height(for metrics: IslandMetrics) -> CGFloat {
        120 * metrics.scale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            header
            if report.map(AttributionRows.showsPlaceholder) ?? true {
                placeholder
            } else if let report {
                // Equal slots share the height left under the header, so rows never overflow at any scale: four at
                // the ideal height, more when the page offers more.
                GeometryReader { proxy in
                    let slots = AttributionRows.slotCount(height: proxy.size.height, metrics: metrics)
                    let rows = AttributionRows.rows(from: report, maximum: slots, l10n: l10n)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<slots, id: \.self) { index in
                            Group {
                                if rows.indices.contains(index) {
                                    AttributionRowView(row: rows[index], accent: style.accent, metrics: metrics, l10n: l10n)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 12 * metrics.scale)
        .padding(.top, 9 * metrics.scale)
        .padding(.bottom, 7 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            minHeight: Self.height(for: metrics),
            idealHeight: Self.height(for: metrics),
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous)
                .fill(Theme.subtleFill)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * metrics.scale) {
            Text(l10n.analytics.whatsEatingLimit)
                .font(metrics.font(12, .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6 * metrics.scale)
            if let note = AttributionRows.note(for: report, l10n: l10n) {
                Text(note)
                    .font(metrics.font(10.5, .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var placeholder: some View {
        Label(l10n.analytics.noTokenData, systemImage: "circle.dashed")
            .font(metrics.font(11, .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row: title, a share bar and the value, with the value's width reserved for its widest text.
private struct AttributionRowView: View {
    let row: AttributionRow
    let accent: Color
    let metrics: IslandMetrics
    let l10n: Localizer

    var body: some View {
        HStack(spacing: 8 * metrics.scale) {
            Text(row.title)
                .font(metrics.font(11.5, row.isOther ? .regular : .medium))
                .foregroundStyle(row.isOther ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShareBar(share: row.share, color: row.isOther ? Color.primary.opacity(0.35) : accent, metrics: metrics)
                .frame(width: 118 * metrics.scale)
            ZStack(alignment: .trailing) {
                Text(AttributionRows.valueTemplate(l10n: l10n))
                    .hidden()
                Text(row.valueText)
                    .foregroundStyle(row.isOther ? .secondary : .primary)
            }
            .font(metrics.digits(11, .semibold))
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        // A session reads "Codometer, 3f9a1c": VoiceOver text never has " · ".
        .accessibilityLabel(row.title.replacingOccurrences(of: " · ", with: ", "))
        .accessibilityValue(AttributionRows.valueA11y(share: row.share, estimatedPoints: row.estimatedPoints, l10n: l10n))
    }
}

/// A thin capsule filled to the share, drawn without animation.
private struct ShareBar: View {
    let share: Double
    let color: Color
    let metrics: IslandMetrics

    var body: some View {
        let height = 6 * metrics.scale
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if share > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, proxy.size.width * CGFloat(min(max(share, 0), 1))))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Rows

/// One displayed attribution row.
struct AttributionRow: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    /// 0…1 of all attributed usage.
    let share: Double
    /// ≈ percentage points of the reference window, when known.
    let estimatedPoints: Double?
    /// "≈3.2%" when the points are known, else the share: "41%".
    let valueText: String

    init(id: String, title: String, share: Double, estimatedPoints: Double?, l10n: Localizer) {
        self.id = id
        self.title = title
        self.share = share
        self.estimatedPoints = estimatedPoints
        valueText = AttributionRows.valueText(share: share, estimatedPoints: estimatedPoints, l10n: l10n)
    }

    var isOther: Bool { id == UsageAttribution.otherShareID }
}

/// Pure decisions for `AttributionListView`.
enum AttributionRows {
    /// Rows at the list's ideal height.
    static let maximumRows = 4
    /// Rows a taller list may show: every named share and "Other".
    static let maximumSlots = UsageAttribution.maximumNamedShares + 1
    /// The widest value text in this language, for reserving the value column's width.
    static func valueTemplate(l10n: Localizer) -> String {
        l10n.analytics.valueTemplate
    }

    /// The report's shares as at most `maximum` rows: when there are more, the first `maximum − 1` stay and the
    /// rest (including any existing "Other") fold into one "Other" row whose points are known only when all were.
    static func rows(from report: AttributionReport, maximum: Int = maximumRows, l10n: Localizer) -> [AttributionRow] {
        let limit = max(1, maximum)
        let shares = report.shares
        guard shares.count > limit else {
            return shares.map {
                AttributionRow(id: $0.id, title: title(of: $0.subject, l10n: l10n), share: $0.share, estimatedPoints: $0.estimatedPoints, l10n: l10n)
            }
        }
        let kept = shares.prefix(limit - 1).map {
            AttributionRow(id: $0.id, title: title(of: $0.subject, l10n: l10n), share: $0.share, estimatedPoints: $0.estimatedPoints, l10n: l10n)
        }
        let rest = shares.dropFirst(limit - 1)
        let share = min(1, rest.reduce(0) { $0 + $1.share })
        let allPointsKnown = rest.allSatisfy { $0.estimatedPoints != nil }
        let points = allPointsKnown ? rest.reduce(0) { $0 + ($1.estimatedPoints ?? 0) } : nil
        return kept + [AttributionRow(
            id: UsageAttribution.otherShareID,
            title: title(of: .other, l10n: l10n),
            share: share,
            estimatedPoints: points,
            l10n: l10n
        )]
    }

    /// A share's subject in words: the project folder, the session label, "Other" or "No project".
    static func title(of subject: AttributionSubject, l10n: Localizer) -> String {
        switch subject {
        case .project(let name): name
        case .session(let parts): UsageFormat.sessionLabel(parts, l10n: l10n)
        case .other: l10n.analyticsFormat.other
        case .noProject: l10n.analyticsFormat.noProject
        }
    }

    /// VoiceOver for a row's value: "about 3.2%" instead of "≈3.2%", else the share.
    static func valueA11y(share: Double, estimatedPoints: Double?, l10n: Localizer) -> String {
        if let estimatedPoints {
            return l10n.analytics.pointsA11y(estimatedPoints)
        }
        return AnalyticsText.percent(share * 100, l10n: l10n)
    }

    static func valueText(share: Double, estimatedPoints: Double?, l10n: Localizer) -> String {
        if let estimatedPoints {
            return UsageFormat.attributionPoints(estimatedPoints, l10n: l10n)
        }
        return AnalyticsText.percent(share * 100, l10n: l10n)
    }

    /// How many equal row slots fit `height` (the space under the header) without rows closer than about 1.4
    /// lines: `maximumRows` at the list's ideal height at any scale, up to `maximumSlots` when taller.
    static func slotCount(height: CGFloat, metrics: IslandMetrics) -> Int {
        let pitch = max(metrics.textSize(11.5) * 1.4, 20 * metrics.scale)
        guard height.isFinite, pitch > 0 else { return maximumRows }
        return min(max(Int((height / pitch).rounded(.down)), maximumRows), maximumSlots)
    }

    /// Whether the list shows "No token data for this period".
    static func showsPlaceholder(_ report: AttributionReport?) -> Bool {
        report.map { $0.shares.isEmpty } ?? true
    }

    /// The header note: "Data since 2:20 PM" when token data starts after the period does, "Estimated from tokens"
    /// otherwise; `nil` without rows. Dates read relative to the period's end, which is when it was loaded.
    static func note(for report: AttributionReport?, l10n: Localizer) -> String? {
        guard let report, !report.isEmpty else { return nil }
        return AnalyticsText.coverageNote(
            coverageStart: report.coverageStart,
            intervalStart: report.interval.start,
            now: report.interval.end,
            l10n: l10n
        ) ?? l10n.analytics.estimatedFromTokens
    }
}
