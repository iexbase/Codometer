import CodometerCore
import SwiftUI
import WidgetKit

/// The island's ring grammar, drawn statically for the widget: a gradient usage arc, a "now" notch at the elapsed
/// share of the window, a glowing filament where usage runs ahead of time, and day ticks inside weekly rings.
///
/// The notch sits in a real gap cut out of the ring with a mask rather than a colour, so it stays legible in the
/// accented and vibrant rendering modes, where the system replaces every colour.
///
/// While an agent of the account waits, a thin attention halo circles the ring — the island's waiting ring, held
/// still. It is drawn outside the ring's frame, so a waiting account's ring is never smaller than the others.
///
/// A `companion` window is drawn as a thinner inner ring with its own notch, so one glance compares the short and
/// the long window; day ticks give way to it.
///
/// Ahead of the used arc, a dashed ghost shows where usage lands by the reset at the pace so far — `forecastPolicy`
/// decides whether it is drawn. It never appears on a stale ring, whose numbers are already out of date, never on the
/// inner companion ring, and never at all when the user turned "Forecast at reset" off (the snapshot says so and
/// `WidgetWindowState.forecast` is then `nil`).
struct WidgetRing<Center: View>: View {
    /// `nil` draws the dashed no-data ring.
    let window: WidgetWindowState?
    var companion: WidgetWindowState?
    let isStale: Bool
    let lineWidth: CGFloat
    var showsTicks = true
    var isWaiting = false
    var forecastPolicy = WidgetForecastPolicy.never
    let palette: WidgetPalette
    @ViewBuilder let center: () -> Center

    /// Space between the outer ring and the companion ring; clears both notches.
    private var companionGap: CGFloat { max(3, lineWidth * 0.55) }
    private var companionLineWidth: CGFloat { max(2.5, lineWidth * 0.62) }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let window {
                    usage(window, side: side, lineWidth: lineWidth, showsTicks: showsTicks && companion == nil, forecastPolicy: forecastPolicy)
                    if let companion {
                        let inner = max(0, side - 2 * (lineWidth + companionGap))
                        ZStack {
                            usage(companion, side: inner, lineWidth: companionLineWidth, showsTicks: false, forecastPolicy: .never)
                        }
                        .frame(width: inner, height: inner)
                    }
                } else {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .stroke(palette.track, style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round, dash: [0.1, lineWidth * 1.35]))
                }
                center()
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if isWaiting {
                Circle()
                    .strokeBorder(palette.attention, lineWidth: haloWidth)
                    .padding(-(haloGap + haloWidth))
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
        }
    }

    /// Clears the tip of the notch, which reaches `0.4 × lineWidth` past the ring.
    private var haloGap: CGFloat { max(2.5, lineWidth * 0.62) }
    private var haloWidth: CGFloat { max(1.5, lineWidth * 0.28) }

    @ViewBuilder
    private func usage(
        _ window: WidgetWindowState,
        side: CGFloat,
        lineWidth: CGFloat,
        showsTicks: Bool,
        forecastPolicy: WidgetForecastPolicy
    ) -> some View {
        let used = window.progress.used
        let colors = palette.arc(window.band, isStale: isStale)
        let radius = side / 2 - lineWidth / 2
        let notch = window.hasResetSinceCapture ? nil : window.progress.elapsed
        let notchWidth = max(1.5, lineWidth * 0.26)
        let notchLength = lineWidth * 1.8

        if showsTicks, window.progress.tickCount > 1, side >= 44 {
            DialTicks(count: window.progress.tickCount, radius: radius - lineWidth * 0.95, length: max(2, lineWidth * 0.42))
                .stroke(palette.secondary.opacity(0.5), style: StrokeStyle(lineWidth: max(1, lineWidth * 0.16), lineCap: .round))
        }

        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(palette.track, lineWidth: lineWidth)

            if !isStale, let forecast = window.forecast, let end = forecastPolicy.arcEnd(for: window) {
                // The ghost starts where the used arc ends, so the two read as one movement, and it is dashed so it
                // stays a hint even where colour is taken away (accented and vibrant rendering).
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: used, to: end)
                    .stroke(
                        palette.forecast(forecast.band),
                        style: StrokeStyle(
                            lineWidth: lineWidth * 0.42,
                            lineCap: .round,
                            dash: [max(1.2, lineWidth * 0.55), max(1.6, lineWidth * 0.7)]
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }

            if used > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: used)
                    .stroke(
                        AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(max(1, 360 * used))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }

            if used >= 1, palette.style == .fullColor {
                // A full ring ends on its own start: a shaded end cap hides the gradient seam, like Activity rings.
                Circle()
                    .fill(colors[1])
                    .frame(width: lineWidth, height: lineWidth)
                    .shadow(color: .black.opacity(0.35), radius: lineWidth * 0.25, x: lineWidth * 0.18)
                    .offset(y: -radius)
            }

            if let elapsed = window.progress.elapsed, window.progress.overrun > 0.015, !isStale, !window.isExhausted,
               palette.style == .fullColor {
                // A bright filament inside the arc where usage runs ahead of time, glowing in the arc's own colour.
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: elapsed, to: used)
                    .stroke(Color.white.opacity(palette.scheme == .dark ? 0.62 : 0.75), style: StrokeStyle(lineWidth: max(1, lineWidth * 0.26), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: palette.overrunGlow(window.band), radius: lineWidth * 0.7)
            }
        }
        .mask {
            if let notch {
                NotchCut(angle: notch, radius: radius, width: notchWidth + max(2, lineWidth * 0.3), length: notchLength + 2)
                    .fill(style: FillStyle(eoFill: true))
            } else {
                Rectangle()
            }
        }

        if let notch {
            Capsule()
                .fill(palette.primary)
                .frame(width: notchWidth, height: notchLength)
                .offset(y: -radius)
                .rotationEffect(.degrees(360 * min(max(notch, 0), 1)))
        }
    }
}

/// The whole rect minus a small rotated slot across the ring at `angle`; filled even-odd it masks out the slot.
private struct NotchCut: Shape {
    let angle: Double
    let radius: CGFloat
    let width: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -rect.width, dy: -rect.height))
        let slot = CGRect(x: -width / 2, y: -radius - length / 2, width: width, height: length)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: CGFloat(min(max(angle, 0), 1) * 2 * .pi))
        path.addPath(Path(roundedRect: slot, cornerRadius: width / 2), transform: transform)
        return path
    }
}

/// Radial tick marks just inside the ring, one per day for weekly windows.
private struct DialTicks: Shape {
    let count: Int
    let radius: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<count {
            let theta = Double(index) / Double(count) * 2 * .pi - .pi / 2
            let outer = CGPoint(x: center.x + cos(theta) * radius, y: center.y + sin(theta) * radius)
            let inner = CGPoint(x: center.x + cos(theta) * (radius - length), y: center.y + sin(theta) * (radius - length))
            path.move(to: outer)
            path.addLine(to: inner)
        }
        return path
    }
}

/// A thin capsule meter with the same "now" notch as the ring, set in a gap cut out of the meter.
struct WidgetMeter: View {
    let window: WidgetWindowState
    let isStale: Bool
    let height: CGFloat
    let palette: WidgetPalette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let used = window.progress.used
            let notch = window.hasResetSinceCapture ? nil : window.progress.elapsed.map { min(max(width * $0, 1), width - 1) }
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    if used > 0 {
                        Capsule()
                            .fill(LinearGradient(colors: palette.arc(window.band, isStale: isStale), startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(height, width * used))
                            .widgetAccentable()
                    }
                }
                .frame(height: height)
                .mask {
                    if let notch {
                        MeterCut(x: notch, width: 4.5)
                            .fill(style: FillStyle(eoFill: true))
                    } else {
                        Rectangle()
                    }
                }
                if let notch {
                    Capsule()
                        .fill(palette.primary)
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: notch - 0.75)
                }
            }
            .frame(width: width, height: proxy.size.height)
        }
        .frame(height: height + 5)
    }
}

/// The meter's rect minus a vertical slot at `x`.
private struct MeterCut: Shape {
    let x: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -4, dy: -4))
        path.addRect(CGRect(x: x - width / 2, y: rect.minY - 4, width: width, height: rect.height + 8))
        return path
    }
}
