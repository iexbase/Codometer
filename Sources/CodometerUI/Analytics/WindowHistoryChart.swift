import CodometerCore
import CodometerL10n
import Charts
import SwiftUI

/// The headline window's recent usage as a strip chart: usage curve, even-pace diagonal, now rule and projection.
///
/// Always `56 × scale` points tall and as wide as offered, whatever the data, so loading history never
/// resizes the deck. The chart cross-fades with its placeholder when history arrives and never animates its data.
public struct WindowHistoryChart: View {
    let series: HistorySeries?
    let window: LimitWindow
    let now: Date
    let metrics: IslandMetrics

    public init(series: HistorySeries?, window: LimitWindow, now: Date, metrics: IslandMetrics) {
        self.series = series
        self.window = window
        self.now = now
        self.metrics = metrics
    }

    public static func height(for metrics: IslandMetrics) -> CGFloat {
        56 * metrics.scale
    }

    @Environment(\.introAnimationsEnabled) private var introAnimationsEnabled
    @Environment(\.l10n) private var l10n

    public var body: some View {
        let model = HistoryChartModel(series: series, window: window, now: now)
        ZStack {
            if model.isPlaceholder {
                HistoryChartPlaceholder(metrics: metrics)
                    .transition(.opacity)
            } else {
                HistoryPlot(model: model, used: window.used.value, metrics: metrics, labels: HistoryPlot.Labels(l10n: l10n))
                    .transition(.opacity)
            }
        }
        // One cross-fade when history arrives (or runs out). Appearing together with the deck adds no fade of its
        // own, so the chart never lags behind the content around it.
        .animation(introAnimationsEnabled ? Motion.reveal : nil, value: model.isPlaceholder)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height(for: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryChartModel.accessibilitySummary(model: model, window: window, now: now, l10n: l10n))
    }
}

/// The chart itself, separate from `WindowHistoryChart` so it can cross-fade with the placeholder.
///
/// Hidden from accessibility: `WindowHistoryChart` speaks one summary instead of the chart's marks.
private struct HistoryPlot: View {
    /// The value labels of the marks, resolved once per language outside the chart builder.
    struct Labels: Hashable {
        let time: String
        let used: String
        let evenPace: String
        let projection: String
        let now: String
        let reset: String
        let zero: String
        let limit: String
        let series: String

        init(l10n: Localizer) {
            let text = l10n.analytics
            time = text.chartTime
            used = text.chartUsed
            evenPace = text.chartEvenPace
            projection = text.chartProjection
            now = text.chartNow
            reset = text.chartReset
            zero = text.chartZero
            limit = text.chartLimit
            series = text.chartSeries
        }
    }

    let model: HistoryChartModel
    let used: Double
    let metrics: IslandMetrics
    let labels: Labels

    @Environment(\.analyticsStyle) private var style

    var body: some View {
        chart
            // Data changes never morph the curve, even inside the deck's geometry transaction.
            .transaction { $0.animation = nil }
            .padding(.vertical, 4 * metrics.scale)
            .accessibilityHidden(true)
    }

    private var chart: some View {
        let band = style.band(for: used)
        let colors = Theme.colors(for: band)
        let tint = Theme.tint(for: band)
        let line = 2 * metrics.scale

        return Chart {
            // The time left in the window, faintly shaded, so "now" reads against the whole window.
            if let now = model.now, now < model.domain.upperBound {
                RectangleMark(
                    xStart: .value(labels.now, now),
                    xEnd: .value(labels.reset, model.domain.upperBound),
                    yStart: .value(labels.zero, 0),
                    yEnd: .value(labels.limit, 100)
                )
                .foregroundStyle(Color.primary.opacity(0.035))
            }

            // The ceiling and the floor: where the limit runs out and where the window started.
            RuleMark(y: .value(labels.limit, 100))
                .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [1.5, 3]))
                .foregroundStyle(Color.primary.opacity(0.18))
            RuleMark(y: .value(labels.zero, 0))
                .lineStyle(StrokeStyle(lineWidth: 0.75))
                .foregroundStyle(Color.primary.opacity(0.12))

            if let pace = model.evenPace {
                ForEach([pace.from, pace.to]) { point in
                    LineMark(x: .value(labels.time, point.at), y: .value(labels.evenPace, point.used), series: .value(labels.series, "pace"))
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.5, 3.5]))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
            }

            ForEach(model.points) { point in
                AreaMark(x: .value(labels.time, point.at), yStart: .value(labels.zero, 0), yEnd: .value(labels.used, point.used))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.46), tint.opacity(0.16), tint.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            ForEach(model.points) { point in
                LineMark(x: .value(labels.time, point.at), y: .value(labels.used, point.used), series: .value(labels.series, "usage"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            }

            if let projection = model.projection {
                ForEach([projection.from, projection.to]) { point in
                    LineMark(x: .value(labels.time, point.at), y: .value(labels.projection, point.used), series: .value(labels.series, "projection"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5 * metrics.scale, lineCap: .round, dash: [3, 3]))
                        .foregroundStyle(Theme.bandText(for: .exhausted).opacity(0.9))
                }
                PointMark(x: .value(labels.time, projection.to.at), y: .value(labels.projection, projection.to.used))
                    .symbol {
                        Circle()
                            .strokeBorder(Theme.bandText(for: .exhausted), lineWidth: 1.5 * metrics.scale)
                            .frame(width: 6 * metrics.scale, height: 6 * metrics.scale)
                    }
            }

            if let now = model.now {
                RuleMark(x: .value(labels.now, now), yStart: .value(labels.zero, 0), yEnd: .value(labels.limit, 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))
                    .foregroundStyle(Color.primary.opacity(0.24))
            }

            if let current = model.current {
                PointMark(x: .value(labels.time, current.at), y: .value(labels.used, current.used))
                    .symbol {
                        // Band text colour: deep on light glass, bright on dark glass, so the dot always reads.
                        Circle()
                            .fill(Theme.bandText(for: band))
                            .frame(width: 6 * metrics.scale, height: 6 * metrics.scale)
                            .background(Circle().fill(tint.opacity(0.28)).padding(-3 * metrics.scale))
                            .shadow(color: tint.opacity(0.6), radius: 3 * metrics.scale)
                    }
            }
        }
        .chartXScale(domain: model.domain)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// Too little history: a dotted floor with "Collecting history…", in exactly the chart's space.
private struct HistoryChartPlaceholder: View {
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack(alignment: .bottom) {
            Line()
                .stroke(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [0.5, 4.5]))
                .frame(height: 1.25)
                .padding(.bottom, 4 * metrics.scale)
            HStack(spacing: 5 * metrics.scale) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(metrics.font(10.5, .semibold))
                Text(l10n.analytics.collectingHistory)
                    .font(metrics.font(11, .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxHeight: .infinity)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}
