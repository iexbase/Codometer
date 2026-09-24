import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// Wallpapers for judging how legible the glass is: calm light, calm dark, and loud and busy.
enum StageBackdrop: String, CaseIterable, Identifiable {
    case light
    case dark
    case colorful

    var id: String { rawValue }

    func title(_ l10n: Localizer) -> String {
        switch self {
        case .light: l10n.stage.light
        case .dark: l10n.stage.dark
        case .colorful: l10n.stage.colorful
        }
    }

    /// The switcher button's tooltip and VoiceOver name.
    func help(_ l10n: Localizer) -> String {
        switch self {
        case .light: l10n.stage.lightHelp
        case .dark: l10n.stage.darkHelp
        case .colorful: l10n.stage.colorfulHelp
        }
    }

    /// Menu bar text is dark on the light wallpaper, white elsewhere.
    var prefersDarkChrome: Bool { self == .light }

    /// A small gradient that stands for the wallpaper in the switcher.
    var swatch: LinearGradient {
        switch self {
        case .light:
            LinearGradient(colors: [Color(red: 0.80, green: 0.88, blue: 1.00), Color(red: 1.00, green: 0.88, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dark:
            LinearGradient(colors: [Color(red: 0.20, green: 0.18, blue: 0.42), Color(red: 0.03, green: 0.04, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .colorful:
            LinearGradient(colors: [.orange, .pink, .purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// The wallpaper of the mock display. Static drawing only: nothing here animates or redraws on its own.
struct StageWallpaper: View {
    let backdrop: StageBackdrop

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch backdrop {
            case .light: light(size)
            case .dark: dark(size)
            case .colorful: colorful(size)
            }
        }
        .accessibilityHidden(true)
    }

    private func light(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.84, green: 0.90, blue: 0.99), Color(red: 0.97, green: 0.96, blue: 0.99), Color(red: 0.99, green: 0.90, blue: 0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            glow(Color(red: 0.55, green: 0.74, blue: 1.00).opacity(0.55), size: size, width: 0.75, height: 0.9, x: -0.28, y: 0.22)
            glow(Color(red: 1.00, green: 0.72, blue: 0.78).opacity(0.5), size: size, width: 0.6, height: 0.7, x: 0.32, y: -0.26)
            glow(Color.white.opacity(0.7), size: size, width: 0.5, height: 0.35, x: 0.05, y: 0.05)
        }
    }

    private func dark(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.07, blue: 0.16), Color(red: 0.10, green: 0.07, blue: 0.20), Color(red: 0.02, green: 0.03, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            glow(Color(red: 0.30, green: 0.24, blue: 0.80).opacity(0.55), size: size, width: 0.8, height: 0.9, x: -0.3, y: 0.3)
            glow(Color(red: 0.02, green: 0.48, blue: 0.58).opacity(0.4), size: size, width: 0.6, height: 0.6, x: 0.35, y: -0.3)
        }
    }

    private func colorful(_ size: CGSize) -> some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.45], [0.42, 0.58], [1, 0.4],
                    [0, 1], [0.6, 1], [1, 1],
                ],
                colors: [
                    Color(red: 1.00, green: 0.55, blue: 0.10), Color(red: 1.00, green: 0.22, blue: 0.52), Color(red: 0.55, green: 0.22, blue: 0.95),
                    Color(red: 1.00, green: 0.86, blue: 0.20), Color(red: 0.98, green: 0.98, blue: 1.00), Color(red: 0.10, green: 0.62, blue: 1.00),
                    Color(red: 0.12, green: 0.80, blue: 0.45), Color(red: 0.00, green: 0.78, blue: 0.85), Color(red: 0.10, green: 0.16, blue: 0.55),
                ]
            )
            Canvas { context, canvasSize in
                // Diagonal stripes and rings: busy detail right behind where the island sits.
                var stripes = Path()
                let spacing: CGFloat = 26
                var offset: CGFloat = -canvasSize.height
                while offset < canvasSize.width {
                    stripes.move(to: CGPoint(x: offset, y: canvasSize.height))
                    stripes.addLine(to: CGPoint(x: offset + canvasSize.height, y: 0))
                    offset += spacing
                }
                context.stroke(stripes, with: .color(.white.opacity(0.16)), lineWidth: 5)
                let rings: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.3, 0.16), (0.78, 0.22, 0.12), (0.62, 0.74, 0.2), (0.5, 0.08, 0.07)]
                for (x, y, radius) in rings {
                    let r = radius * min(canvasSize.width, canvasSize.height)
                    let rect = CGRect(x: x * canvasSize.width - r, y: y * canvasSize.height - r, width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.28)), lineWidth: 9)
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: 14, dy: 14)), with: .color(.white.opacity(0.45)), lineWidth: 3)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func glow(_ color: Color, size: CGSize, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: size.width * width, height: size.height * height)
            .blur(radius: min(size.width, size.height) * 0.14)
            .offset(x: size.width * x, y: size.height * y)
    }
}

/// The mock macOS menu bar, drawn in virtual screen points, in the interface language and the user's clock.
struct StageMenuBar: View {
    let backdrop: StageBackdrop
    let width: CGFloat

    @Environment(\.l10n) private var l10n

    /// The clock's fixed time: a Thursday at 12:10 in the calendar's time zone (the drawing never changes on its own).
    static func clockDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12, minute: 10)) ?? Date(timeIntervalSince1970: 1_789_647_000)
    }

    var body: some View {
        let height = SettingsStageGeometry.menuBarHeight
        let ink: Color = backdrop.prefersDarkChrome ? .black.opacity(0.82) : .white.opacity(0.94)
        HStack(spacing: 18) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 13, weight: .semibold))
            // The app's name is the same in every language.
            Text(verbatim: "Finder").font(.system(size: 13, weight: .bold))
            ForEach([l10n.stage.menuFile, l10n.stage.menuEdit, l10n.stage.menuView, l10n.stage.menuWindow], id: \.self) { item in
                Text(item).font(.system(size: 13))
            }
            Spacer(minLength: 0)
            Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
            Image(systemName: "battery.75percent").font(.system(size: 14))
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
            Text(l10n.stage.menuBarClock(Self.clockDate(in: l10n.calendar))).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .frame(width: width, height: height)
        .background(backdrop.prefersDarkChrome ? Color.white.opacity(0.38) : Color.black.opacity(0.18))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The camera notch of the mock display, drawn over the mock menu bar in virtual screen points.
///
/// Shown only when the display the island really sits on has one, so the preview never promises a fusion the Mac
/// cannot do.
struct StageNotch: View {
    let notch: NotchGeometry
    let screenWidth: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: notch.menuBarHeight * 0.3,
            bottomTrailingRadius: notch.menuBarHeight * 0.3,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Color.black)
        .frame(width: notch.rect.width, height: notch.menuBarHeight)
        .offset(x: notch.rect.minX)
        .frame(width: screenWidth, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The mock Dock, drawn in virtual screen points.
struct StageDock: View {
    private static let tiles: [[Color]] = [
        [Color(red: 0.35, green: 0.78, blue: 1.00), Color(red: 0.10, green: 0.45, blue: 0.95)],
        [Color(red: 0.55, green: 0.92, blue: 0.45), Color(red: 0.12, green: 0.66, blue: 0.30)],
        [Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 0.98, green: 0.48, blue: 0.10)],
        [Color(red: 0.98, green: 0.42, blue: 0.52), Color(red: 0.84, green: 0.14, blue: 0.36)],
        [Color(red: 0.72, green: 0.52, blue: 1.00), Color(red: 0.44, green: 0.22, blue: 0.86)],
        [Color(red: 0.40, green: 0.40, blue: 0.44), Color(red: 0.12, green: 0.12, blue: 0.14)],
        [Color(red: 0.92, green: 0.92, blue: 0.95), Color(red: 0.70, green: 0.72, blue: 0.78)],
    ]

    var body: some View {
        let tile = SettingsStageGeometry.dockHeight - 14
        HStack(spacing: 8) {
            ForEach(Self.tiles.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: tile * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: Self.tiles[index], startPoint: .top, endPoint: .bottom))
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: SettingsStageGeometry.dockHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The aluminium frame around the mock display.
struct StageBezel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.23, green: 0.24, blue: 0.27), Color(red: 0.10, green: 0.10, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
            .accessibilityHidden(true)
    }
}
