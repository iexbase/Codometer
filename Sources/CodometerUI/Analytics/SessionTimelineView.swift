import CodometerCore
import CodometerL10n
import SwiftUI

/// One account's sessions as lanes of working and waiting time under the headline usage curve.
///
/// Ideally `150 × scale` points tall (never shorter) and as wide as offered, whatever the data, so loading never
/// resizes the deck. Offered more height (the Timeline page fills the height the deck sizes to its tallest page), the
/// curve grows and more lanes fit; that height too comes from the layout, never from the data. Drawn with one
/// `Canvas` that redraws only when the data changes; the hover scrub is a separate light layer, and only lane titles
/// and the tooltip are views. Hovering scrubs a line with "2:32 PM · 2 agents · 41%". Nothing animates on its own.
public struct SessionTimelineView: View {
    let snapshot: TimelineSnapshot?
    let now: Date
    let metrics: IslandMetrics
    /// A hover position shown while the pointer is elsewhere; only for static snapshot renders.
    var previewHoverX: CGFloat?

    @Environment(\.analyticsStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.l10n) private var l10n
    @State private var hoverX: CGFloat?

    public init(snapshot: TimelineSnapshot?, now: Date, metrics: IslandMetrics) {
        self.snapshot = snapshot
        self.now = now
        self.metrics = metrics
    }

    /// The ideal (and minimum) height.
    nonisolated public static func height(for metrics: IslandMetrics) -> CGFloat {
        150 * metrics.scale
    }

    public var body: some View {
        GeometryReader { proxy in
            let frame = TimelineFrame(size: proxy.size, metrics: metrics)
            if let snapshot {
                content(snapshot: snapshot, frame: frame)
            } else {
                TimelinePlaceholder(frame: frame, metrics: metrics)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Self.height(for: metrics), idealHeight: Self.height(for: metrics), maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous)
                .fill(Theme.subtleFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimelineLayout.accessibilitySummary(snapshot: snapshot, now: now, l10n: l10n))
    }

    @ViewBuilder
    private func content(snapshot: TimelineSnapshot, frame: TimelineFrame) -> some View {
        let selection = TimelineLayout.lanes(
            segments: snapshot.segments,
            interval: snapshot.interval,
            now: now,
            maximum: frame.laneCapacity,
            l10n: l10n
        )
        let scrubX = hoverX ?? previewHoverX
        let hoverDate = scrubX.flatMap { TimelineLayout.date(atX: $0, plot: frame.plotX, interval: snapshot.interval) }
        let currentUsage = snapshot.usage?.points.last?.used

        ZStack(alignment: .topLeading) {
            // Equatable, so pointer moves redraw only the scrub layer on top of it, never the curve and lanes.
            TimelineCanvas(
                snapshot: snapshot,
                lanes: selection.lanes,
                now: now,
                frame: frame,
                style: style,
                metrics: metrics,
                colorScheme: colorScheme,
                l10n: l10n
            )
            .equatable()

            if let hoverDate {
                TimelineScrub(
                    usage: snapshot.usage,
                    interval: snapshot.interval,
                    hoverDate: hoverDate,
                    // Inside a gap the carried value is not a recorded one, so the dot on the curve stays away.
                    isInGap: TimelineLayout.gap(at: hoverDate, in: snapshot.gaps) != nil,
                    frame: frame,
                    style: style,
                    metrics: metrics
                )
            }

            // Gutter: the limit's current value beside the curve, then one title per lane.
            VStack(alignment: .leading, spacing: 0) {
                Text(l10n.analytics.limitCaption)
                    .font(metrics.font(10.5, .medium))
                    .foregroundStyle(.secondary)
                Text(currentUsage.map { AnalyticsText.percent($0, l10n: l10n) } ?? "—")
                    .font(metrics.digits(14, .bold))
                    .foregroundStyle(currentUsage.map { Theme.bandText(for: style.band(for: $0)) } ?? Color.secondary)
            }
            .lineLimit(1)
            .frame(width: frame.gutterWidth, height: frame.curve.height, alignment: .leading)
            .offset(x: frame.gutterX, y: frame.curve.minY)

            ForEach(Array(selection.lanes.enumerated()), id: \.element.id) { index, lane in
                LaneTitle(lane: lane, style: style, metrics: metrics)
                    .frame(width: frame.gutterWidth, height: frame.lanePitch, alignment: .leading)
                    .offset(x: frame.gutterX, y: frame.laneMinY(index))
            }

            if let overflow = selection.overflowText(l10n: l10n) {
                Text(overflow)
                    .font(metrics.font(10.5, .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: frame.gutterWidth, height: frame.tickRow.height, alignment: .leading)
                    .offset(x: frame.gutterX, y: frame.tickRow.minY)
            }

            if let hoverDate, let scrubX {
                TimelineTooltip(
                    text: TimelineLayout.tooltip(at: hoverDate, snapshot: snapshot, now: now, l10n: l10n),
                    anchorX: scrubX,
                    width: frame.size.width,
                    metrics: metrics
                )
            }
        }
        .frame(width: frame.size.width, height: frame.size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let inside = frame.plotX.contains(location.x) && location.y >= frame.curve.minY && location.y <= frame.tickRow.maxY
                hoverX = inside ? location.x : nil
            case .ended:
                hoverX = nil
            }
        }
        .onDisappear { hoverX = nil }
    }
}

// MARK: - Geometry

/// Every rectangle of the timeline, derived from its size and scale so drawing and overlays agree.
struct TimelineFrame: Equatable {
    let size: CGSize
    let gutterX: CGFloat
    let gutterWidth: CGFloat
    /// Horizontal extent of the time axis.
    let plotX: ClosedRange<CGFloat>
    let curve: CGRect
    let lanesArea: CGRect
    /// Lanes that fit with titles at least 1.25 lines apart: five at full scale, fewer when text size floors
    /// make titles large relative to the view (four at scale 0.85), up to `maximumLaneCapacity` when taller.
    let laneCapacity: Int
    let lanePitch: CGFloat
    let capsuleHeight: CGFloat
    let tickRow: CGRect
    /// Vertical centre of the reset glyphs, in the band above the curve's ceiling.
    let resetGlyphY: CGFloat

    init(size: CGSize, metrics: IslandMetrics) {
        let scale = metrics.scale
        let horizontalPadding = 12 * scale
        let topPadding = 15 * scale
        let bottomPadding = 6 * scale
        self.size = size
        let titleSize = metrics.textSize(10.5)
        gutterX = horizontalPadding
        // Titles keep their size floor at small scales, so the gutter follows the text rather than the scale.
        // About a dozen characters: lanes are titled by project folder, and a wider gutter would crowd the ticks.
        gutterWidth = Self.gutterDesignWidth * max(scale, titleSize / 11)
        let plotStart = horizontalPadding + gutterWidth + 8 * scale
        let plotEnd = max(plotStart + 1, size.width - horizontalPadding)
        plotX = plotStart...plotEnd

        // Height beyond the ideal goes partly to the curve, the rest to the lanes.
        let extra = max(0, size.height - SessionTimelineView.height(for: metrics))
        let tickHeight = metrics.textSize(10.5) + 3
        tickRow = CGRect(x: plotStart, y: size.height - bottomPadding - tickHeight, width: plotEnd - plotStart, height: tickHeight)
        curve = CGRect(x: plotStart, y: topPadding, width: plotEnd - plotStart, height: 34 * scale + extra * Self.curveShareOfExtra)
        resetGlyphY = topPadding - 7 * scale
        let lanesTop = curve.maxY + 7 * scale
        let lanesBottom = max(lanesTop, tickRow.minY - 2 * scale)
        lanesArea = CGRect(x: plotStart, y: lanesTop, width: plotEnd - plotStart, height: lanesBottom - lanesTop)
        let fitting = Int((lanesArea.height / (titleSize * Self.minimumLaneLines)).rounded(.down))
        laneCapacity = min(max(1, fitting), Self.maximumLaneCapacity)
        lanePitch = lanesArea.height / CGFloat(laneCapacity)
        capsuleHeight = max(4, min(lanePitch * 0.52, 7 * scale))
    }

    /// Lane pitch in title line heights (point size × this) below which a lane is dropped.
    static let minimumLaneLines: CGFloat = 1.25
    /// The lane title column at scale 1, before text size floors widen it.
    static let gutterDesignWidth: CGFloat = 82
    /// Part of any height beyond the ideal that the usage curve takes.
    static let curveShareOfExtra: CGFloat = 0.35
    /// Lanes a taller timeline may show; at the ideal height the lanes area fits five at most.
    static let maximumLaneCapacity = 7

    func laneMinY(_ index: Int) -> CGFloat {
        lanesArea.minY + lanePitch * CGFloat(index)
    }

    func laneMidY(_ index: Int) -> CGFloat {
        laneMinY(index) + lanePitch / 2
    }

    func x(_ date: Date, interval: DateInterval) -> CGFloat {
        TimelineLayout.x(of: date, plot: plotX, interval: interval)
    }

    /// A usage value's position on the curve.
    func point(_ date: Date, _ used: Double, interval: DateInterval) -> CGPoint {
        CGPoint(
            x: x(date, interval: interval),
            y: curve.maxY - curve.height * CGFloat(min(max(used, 0), 100) / 100)
        )
    }
}

// MARK: - Drawing

private struct TimelineCanvas: View, Equatable {
    let snapshot: TimelineSnapshot
    let lanes: [TimelineLane]
    let now: Date
    let frame: TimelineFrame
    let style: AnalyticsStyle
    let metrics: IslandMetrics
    /// Not drawn with directly: part of equality so a light/dark switch redraws the appearance-dependent colours.
    let colorScheme: ColorScheme
    /// Part of equality too, so a language or region change redraws the tick and coverage labels.
    let l10n: Localizer

    private var interval: DateInterval { snapshot.interval }

    var body: some View {
        Canvas { context, _ in
            let ticks = tickDates()
            // Stretches the app did not record. Everything below them knows where they are: the curve breaks, the
            // lane tracks stop and the "no sessions" note steps aside, so a gap never reads as idle time.
            let gaps = TimelineLayout.gapSpans(snapshot.gaps, interval: interval, plot: frame.plotX)
            drawGrid(ticks: ticks.dates, in: &context)
            let reserved = drawCoverage(gaps: gaps, in: &context)
            drawGaps(gaps, in: &context)
            drawCurve(gaps: gaps, in: &context)
            drawLanes(gaps: gaps, in: &context)
            // Last of the plot, so the labels stay legible over the hatch, the curve and the lanes.
            drawGapLabels(gaps, in: &context)
            drawTickLabels(ticks: ticks.dates, step: ticks.step, reserved: reserved, in: &context)
        }
        .accessibilityHidden(true)
    }

    private func tickDates() -> (dates: [Date], step: TimeInterval) {
        let step = TimelineLayout.tickStep(
            duration: interval.duration,
            width: frame.plotX.upperBound - frame.plotX.lowerBound,
            minimumSpacing: 46 * metrics.scale
        )
        return (TimelineLayout.ticks(in: interval, step: step), step)
    }

    private func drawGrid(ticks: [Date], in context: inout GraphicsContext) {
        var grid = Path()
        for tick in ticks {
            let x = frame.x(tick, interval: interval)
            grid.move(to: CGPoint(x: x, y: frame.curve.minY))
            grid.addLine(to: CGPoint(x: x, y: frame.lanesArea.maxY))
        }
        context.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 0.75)

        // Ceiling (100 %) and floor of the usage curve.
        var ceiling = Path()
        ceiling.move(to: CGPoint(x: frame.plotX.lowerBound, y: frame.curve.minY))
        ceiling.addLine(to: CGPoint(x: frame.plotX.upperBound, y: frame.curve.minY))
        context.stroke(ceiling, with: .color(.primary.opacity(0.14)), style: StrokeStyle(lineWidth: 0.75, dash: [1.5, 3]))
        var floor = Path()
        floor.move(to: CGPoint(x: frame.plotX.lowerBound, y: frame.curve.maxY))
        floor.addLine(to: CGPoint(x: frame.plotX.upperBound, y: frame.curve.maxY))
        context.stroke(floor, with: .color(.primary.opacity(0.12)), lineWidth: 0.75)
    }

    /// Dims the part of the lanes before session data was recorded, labelled "Data since 2:20 PM".
    ///
    /// The label sits inside the dimmed part when it fits; otherwise its short form "Since 2:20 PM" moves to the tick row,
    /// starting at the coverage boundary, and the returned span is kept free of tick labels, so it never covers
    /// lane capsules.
    private func drawCoverage(gaps: [TimelineGapSpan], in context: inout GraphicsContext) -> ClosedRange<CGFloat>? {
        var reserved: ClosedRange<CGFloat>?
        /// Whether "Data since …" sits in the middle of the dimmed part, where nothing else may be drawn.
        var notesDimmedPart = false
        let area = frame.lanesArea
        let coverageX = snapshot.coverageStart.map { frame.x($0, interval: interval) } ?? area.minX
        if let note = AnalyticsText.coverageNote(coverageStart: snapshot.coverageStart, intervalStart: interval.start, now: now, l10n: l10n) {
            let dim = CGRect(x: area.minX, y: area.minY, width: max(0, coverageX - area.minX), height: area.height)
            let shape = Path(roundedRect: dim, cornerRadius: 5 * metrics.scale, style: .continuous)
            context.fill(shape, with: .color(.primary.opacity(0.035)))
            var hatch = context
            hatch.clip(to: shape)
            hatch.stroke(stripes(in: dim, spacing: 6 * metrics.scale), with: .color(.primary.opacity(0.06)), lineWidth: 1)

            var boundary = Path()
            boundary.move(to: CGPoint(x: coverageX, y: frame.curve.maxY + 2 * metrics.scale))
            boundary.addLine(to: CGPoint(x: coverageX, y: area.maxY))
            context.stroke(boundary, with: .color(.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 2.5]))

            let label = context.resolve(
                Text(note).font(metrics.font(10.5, .medium)).foregroundStyle(.secondary)
            )
            let labelSize = label.measure(in: CGSize(width: area.width, height: area.height))
            let inset = 6 * metrics.scale
            if dim.width >= labelSize.width + 2 * inset {
                context.draw(label, at: CGPoint(x: dim.midX, y: area.midY), anchor: .center)
                notesDimmedPart = true
            } else if let coverageStart = snapshot.coverageStart {
                let short = context.resolve(
                    Text(AnalyticsText.coverageShortNote(coverageStart: coverageStart, now: now, l10n: l10n))
                        .font(metrics.digits(10.5, .semibold))
                        .foregroundStyle(.secondary)
                )
                let shortSize = short.measure(in: CGSize(width: frame.tickRow.width, height: frame.tickRow.height))
                let span = TimelineLayout.tickRowNoteSpan(
                    boundaryX: coverageX,
                    labelWidth: shortSize.width,
                    row: frame.tickRow.minX...frame.tickRow.maxX
                )
                context.draw(short, at: CGPoint(x: span.lowerBound, y: frame.tickRow.midY), anchor: .leading)
                reserved = span
            }
        }

        if lanes.isEmpty {
            let start = min(max(area.minX, coverageX), area.maxX)
            let message = context.resolve(
                Text(l10n.analytics.noSessionsInPeriod).font(metrics.font(11, .medium)).foregroundStyle(.secondary)
            )
            let size = message.measure(in: area.size)
            // Inside a gap the message would be wrong ("no sessions" there means "nothing was recorded"), so it
            // takes the widest stretch that is neither dimmed nor a gap.
            if let center = TimelineLayout.messageCenter(in: start...area.maxX, avoiding: gaps, width: size.width) {
                context.draw(message, at: CGPoint(x: center, y: area.midY), anchor: .center)
            } else if !notesDimmedPart,
                      let center = TimelineLayout.messageCenter(in: area.minX...area.maxX, avoiding: gaps, width: size.width) {
                context.draw(message, at: CGPoint(x: center, y: area.midY), anchor: .center)
            }
            // Otherwise the recorded part is too narrow for the message (coverage starts at or near the end of the
            // period, which it may, or gaps take the rest): "Data since …" and the gap labels say why the lanes
            // are empty.
        }
        return reserved
    }

    /// Marks every stretch without collected data across the curve and the lanes, in the same visual language as
    /// the dimmed part before the coverage start: a faint fill, diagonal stripes and a dashed edge on both sides,
    /// or one plain band when the gap is only a few points wide.
    private func drawGaps(_ gaps: [TimelineGapSpan], in context: inout GraphicsContext) {
        guard !gaps.isEmpty else { return }
        for gap in gaps {
            let rect = CGRect(x: gap.x.lowerBound, y: frame.curve.minY, width: gap.width, height: frame.lanesArea.maxY - frame.curve.minY)
            let shape = Path(roundedRect: rect, cornerRadius: min(5 * metrics.scale, gap.width / 2), style: .continuous)
            // A few points wide (a night's sleep over a week) the stripes and the two edges cannot be told apart,
            // so such a gap is one plain band instead.
            guard gap.width >= TimelineLayout.hatchedGapWidth * metrics.scale else {
                context.fill(shape, with: .color(.primary.opacity(0.11)))
                continue
            }
            context.fill(shape, with: .color(.primary.opacity(0.045)))
            var hatch = context
            hatch.clip(to: shape)
            hatch.stroke(stripes(in: rect, spacing: 6 * metrics.scale), with: .color(.primary.opacity(0.075)), lineWidth: 1)

            var edges = Path()
            for x in [gap.x.lowerBound, gap.x.upperBound] {
                edges.move(to: CGPoint(x: x, y: rect.minY))
                edges.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            context.stroke(edges, with: .color(.primary.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 2.5]))
        }
    }

    /// Names each gap that is wide enough for its phrase; narrower ones stay hatched and speak through the tooltip
    /// and the VoiceOver summary.
    private func drawGapLabels(_ gaps: [TimelineGapSpan], in context: inout GraphicsContext) {
        guard !gaps.isEmpty else { return }
        let area = CGSize(width: frame.plotX.upperBound - frame.plotX.lowerBound, height: frame.lanesArea.maxY - frame.curve.minY)
        for gap in gaps {
            var resolved: [String: GraphicsContext.ResolvedText] = [:]
            let label = TimelineLayout.gapLabel(gap.reason, width: gap.width, l10n: l10n) { phrase in
                let text = resolved[phrase] ?? context.resolve(
                    Text(phrase).font(metrics.font(10.5, .medium)).foregroundStyle(.secondary)
                )
                resolved[phrase] = text
                return text.measure(in: area).width
            }
            guard let label, let text = resolved[label] else { continue }
            let midX = (gap.x.lowerBound + gap.x.upperBound) / 2
            context.draw(text, at: CGPoint(x: midX, y: (frame.curve.minY + frame.lanesArea.maxY) / 2), anchor: .center)
        }
    }

    private func drawCurve(gaps: [TimelineGapSpan], in context: inout GraphicsContext) {
        let vertices = TimelineLayout.curveVertices(series: snapshot.usage, interval: interval, now: now)
        guard let last = vertices.last else {
            let label = context.resolve(
                Text(l10n.analytics.noLimitHistory).font(metrics.font(10.5, .medium)).foregroundStyle(.tertiary)
            )
            context.draw(label, at: CGPoint(x: frame.curve.midX, y: frame.curve.midY), anchor: .center)
            return
        }
        let band = style.band(for: last.used)
        let colors = Theme.colors(for: band)
        let tint = Theme.tint(for: band)

        // One run per recorded stretch: the line is solid inside a run, the fill stops at its ends, and a faint
        // dashed connector crosses each gap, where the values are real but the path between them is not.
        let runs = TimelineLayout.curveRuns(vertices: vertices, gaps: gaps.map(\.interval))
        var line = Path()
        var area = Path()
        for run in runs {
            guard let head = run.first, let tail = run.last else { continue }
            var stroke = Path()
            stroke.move(to: point(head.at, head.used))
            for vertex in run.dropFirst() {
                stroke.addLine(to: point(vertex.at, vertex.used))
            }
            // A run of one vertex would stroke nothing; a zero-length line under a round cap draws its dot.
            if run.count == 1 { stroke.addLine(to: point(head.at, head.used)) }
            line.addPath(stroke)

            var fill = stroke
            fill.addLine(to: CGPoint(x: frame.x(tail.at, interval: interval), y: frame.curve.maxY))
            fill.addLine(to: CGPoint(x: frame.x(head.at, interval: interval), y: frame.curve.maxY))
            fill.closeSubpath()
            area.addPath(fill)
        }
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.34), tint.opacity(0.03)]),
                startPoint: CGPoint(x: 0, y: frame.curve.minY),
                endPoint: CGPoint(x: 0, y: frame.curve.maxY)
            )
        )
        var connectors = Path()
        for (before, after) in zip(runs, runs.dropFirst()) {
            guard let from = before.last, let to = after.first else { continue }
            connectors.move(to: point(from.at, from.used))
            connectors.addLine(to: point(to.at, to.used))
        }
        context.stroke(
            connectors,
            with: .color(tint.opacity(0.4)),
            style: StrokeStyle(lineWidth: 1 * metrics.scale, dash: [2, 3])
        )
        context.stroke(
            line,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: frame.plotX.lowerBound, y: 0),
                endPoint: CGPoint(x: frame.plotX.upperBound, y: 0)
            ),
            style: StrokeStyle(lineWidth: 1.5 * metrics.scale, lineCap: .round, lineJoin: .round)
        )

        // Reset markers: a small reset glyph above the ceiling and a dashed line down to the floor. Over a week a
        // five-hour window resets every few points, so markers closer than a glyph and a gap are left out.
        let glyphSize = max(8, 8.5 * metrics.scale)
        let markerXs = TimelineLayout.resetMarkerXs(
            resets: snapshot.usage?.resets ?? [],
            interval: interval,
            plot: frame.plotX,
            minimumSpacing: glyphSize + 8 * metrics.scale
        )
        guard !markerXs.isEmpty else { return }
        var markers = Path()
        let glyph = context.resolve(
            Text(Image(systemName: "arrow.counterclockwise"))
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(.secondary)
        )
        for x in markerXs {
            markers.move(to: CGPoint(x: x, y: frame.curve.minY))
            markers.addLine(to: CGPoint(x: x, y: frame.curve.maxY))
            context.draw(glyph, at: CGPoint(x: x, y: frame.resetGlyphY), anchor: .center)
        }
        context.stroke(markers, with: .color(.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 2.5]))
    }

    private func point(_ date: Date, _ used: Double) -> CGPoint {
        frame.point(date, used, interval: interval)
    }

    private func drawLanes(gaps: [TimelineGapSpan], in context: inout GraphicsContext) {
        let accent = style.accent
        let height = frame.capsuleHeight
        // Tracks and capsules stop at every gap: nothing was recorded there, so neither an idle track nor a
        // capsule crossing one would be true.
        let canvas = clipped(context, to: gaps)
        // Tracks start where recording starts, so the dimmed part reads as "no data" rather than "idle".
        let partial = AnalyticsText.coverageNote(coverageStart: snapshot.coverageStart, intervalStart: interval.start, now: now, l10n: l10n) != nil
        let trackStart = partial
            ? snapshot.coverageStart.map { frame.x($0, interval: interval) + 3 * metrics.scale } ?? frame.plotX.lowerBound
            : frame.plotX.lowerBound
        for (index, lane) in lanes.enumerated() {
            let midY = frame.laneMidY(index)
            if frame.plotX.upperBound - trackStart > height {
                let track = CGRect(x: trackStart, y: midY - height / 2, width: frame.plotX.upperBound - trackStart, height: height)
                canvas.fill(Path(roundedRect: track, cornerRadius: height / 2), with: .color(.primary.opacity(0.05)))
            }

            for segment in lane.segments {
                guard let span = TimelineLayout.span(of: segment, interval: interval, now: now) else { continue }
                let startX = frame.x(span.lowerBound, interval: interval)
                let endX = frame.x(span.upperBound, interval: interval)
                // Short segments stay visible as dots, kept inside the plot.
                let width = max(height, endX - startX)
                let x = min(startX, frame.plotX.upperBound - width)
                let rect = CGRect(x: x, y: midY - height / 2, width: width, height: height)
                let capsule = Path(roundedRect: rect, cornerRadius: height / 2)
                switch segment.activity {
                case .waiting:
                    canvas.fill(capsule, with: .color(Theme.attention.opacity(0.22)))
                    var hatch = canvas
                    hatch.clip(to: capsule)
                    hatch.stroke(stripes(in: rect, spacing: 3.5 * metrics.scale), with: .color(Theme.attention.opacity(0.95)), lineWidth: 1.25 * metrics.scale)
                    canvas.stroke(capsule, with: .color(Theme.attention.opacity(0.55)), lineWidth: 0.75)
                case .working, .idle:
                    canvas.fill(
                        capsule,
                        with: .linearGradient(
                            Gradient(colors: [accent.opacity(0.95), accent.opacity(0.72)]),
                            startPoint: CGPoint(x: 0, y: rect.minY),
                            endPoint: CGPoint(x: 0, y: rect.maxY)
                        )
                    )
                }
            }
        }
    }

    private func drawTickLabels(
        ticks: [Date],
        step: TimeInterval,
        reserved: ClosedRange<CGFloat>?,
        in context: inout GraphicsContext
    ) {
        let row = frame.tickRow
        var lastMaxX = -CGFloat.infinity
        let gap = 6 * metrics.scale
        for tick in ticks {
            let label = context.resolve(
                Text(TimelineLayout.tickLabel(tick, step: step, l10n: l10n))
                    .font(metrics.digits(10.5, .medium))
                    .foregroundStyle(.secondary)
            )
            let size = label.measure(in: CGSize(width: row.width, height: row.height))
            let centerX = frame.x(tick, interval: interval)
            let minX = min(max(centerX - size.width / 2, row.minX), row.maxX - size.width)
            guard minX >= lastMaxX + gap else { continue }
            if let reserved, minX - gap < reserved.upperBound, minX + size.width + gap > reserved.lowerBound { continue }
            context.draw(label, at: CGPoint(x: minX, y: row.midY), anchor: .leading)
            lastMaxX = minX + size.width

            var tickMark = Path()
            tickMark.move(to: CGPoint(x: centerX, y: frame.lanesArea.maxY))
            tickMark.addLine(to: CGPoint(x: centerX, y: frame.lanesArea.maxY + 2 * metrics.scale))
            context.stroke(tickMark, with: .color(.primary.opacity(0.25)), lineWidth: 1)
        }
    }

    /// A copy of the context that draws only outside the gaps, over the whole lanes area.
    private func clipped(_ context: GraphicsContext, to gaps: [TimelineGapSpan]) -> GraphicsContext {
        guard !gaps.isEmpty else { return context }
        var recorded = Path()
        for range in TimelineLayout.visibleRanges(frame.plotX, without: gaps) {
            recorded.addRect(CGRect(
                x: range.lowerBound,
                y: frame.lanesArea.minY,
                width: range.upperBound - range.lowerBound,
                height: frame.lanesArea.height
            ))
        }
        var clipped = context
        clipped.clip(to: recorded)
        return clipped
    }

    /// Diagonal hatching across a rectangle; clip before stroking.
    private func stripes(in rect: CGRect, spacing: CGFloat) -> Path {
        var path = Path()
        let step = max(2, spacing)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}

/// The hover scrub line and the dot on the curve: a small layer of its own, redrawn on every pointer move.
private struct TimelineScrub: View {
    let usage: HistorySeries?
    let interval: DateInterval
    let hoverDate: Date
    /// Whether the moment lies in a gap, where no value was recorded.
    let isInGap: Bool
    let frame: TimelineFrame
    let style: AnalyticsStyle
    let metrics: IslandMetrics

    var body: some View {
        Canvas { context, _ in
            let x = frame.x(hoverDate, interval: interval)
            var scrub = Path()
            scrub.move(to: CGPoint(x: x, y: frame.curve.minY))
            scrub.addLine(to: CGPoint(x: x, y: frame.lanesArea.maxY))
            context.stroke(scrub, with: .color(.primary.opacity(0.5)), lineWidth: 1)

            if !isInGap, let used = TimelineLayout.usage(at: hoverDate, in: usage) {
                let center = frame.point(hoverDate, used, interval: interval)
                let radius = 3 * metrics.scale
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(Theme.bandText(for: style.band(for: used))))
                context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Overlays

/// A lane's title with a dot showing whether the session is working or waiting right now.
private struct LaneTitle: View {
    let lane: TimelineLane
    let style: AnalyticsStyle
    let metrics: IslandMetrics

    var body: some View {
        HStack(spacing: 5 * metrics.scale) {
            Circle()
                .fill(dotColor)
                .frame(width: 5 * metrics.scale, height: 5 * metrics.scale)
            // Middle truncation keeps the end, where "· 3f9a1c" tells sessions of one project apart.
            Text(lane.title)
                .font(metrics.font(10.5, lane.openActivity == nil ? .regular : .medium))
                .foregroundStyle(lane.openActivity == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var dotColor: Color {
        switch lane.openActivity {
        case .waiting: Theme.attention
        case .working: style.accent
        case .idle, nil: Color.primary.opacity(0.2)
        }
    }
}

/// "2:32 PM · 2 agents · 41%" above the scrub line, kept inside the view's width.
private struct TimelineTooltip: View {
    let text: String
    let anchorX: CGFloat
    let width: CGFloat
    let metrics: IslandMetrics

    var body: some View {
        Text(text)
            .font(metrics.digits(10.5, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7 * metrics.scale)
            .padding(.vertical, 3 * metrics.scale)
            .background {
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            }
            .alignmentGuide(.leading) { dimensions in
                let inset = 4 * metrics.scale
                let left = min(max(anchorX - dimensions.width / 2, inset), max(inset, width - dimensions.width - inset))
                return -left
            }
            .alignmentGuide(.top) { _ in -2 * metrics.scale }
            .allowsHitTesting(false)
    }
}

/// No snapshot yet: the curve's dotted floor and ceiling with a short note, centred in exactly the timeline's space.
private struct TimelinePlaceholder: View {
    let frame: TimelineFrame
    let metrics: IslandMetrics
    @Environment(\.l10n) private var l10n

    var body: some View {
        Canvas { context, _ in
            for (y, opacity) in [(frame.curve.minY, 0.12), (frame.curve.maxY, 0.2)] {
                var line = Path()
                line.move(to: CGPoint(x: frame.gutterX, y: y))
                line.addLine(to: CGPoint(x: frame.plotX.upperBound, y: y))
                context.stroke(line, with: .color(.primary.opacity(opacity)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [0.5, 4.5]))
            }
        }
        .overlay {
            Label(l10n.analytics.timelineEmpty, systemImage: "chart.bar.xaxis")
                .font(metrics.font(11, .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .position(x: (frame.gutterX + frame.plotX.upperBound) / 2, y: frame.lanesArea.midY)
        }
    }
}
