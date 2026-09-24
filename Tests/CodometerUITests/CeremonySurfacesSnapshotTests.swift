import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import QuartzCore
import SwiftUI
import Testing

/// PNGs for review, in English and Russian: each surface celebrating a limit reset, and the Presentation pane's
/// Behavior section for both styles. Runs only with `CODOMETER_SNAPSHOT_DIR`, e.g.
/// `CODOMETER_SNAPSHOT_DIR=/tmp/shots Scripts/test.sh --filter CeremonySurfacesSnapshotTests`.
///
/// **How the ceremony frames are drawn.** The ceremony is two one-shot Core Animation runs, and neither
/// `ImageRenderer` nor `cacheDisplay` can capture a presentation frame (and ScreenCaptureKit can fail with −3811 without
/// Screen Recording permission). So each image is made from the real view tree: the surface is hosted and laid out,
/// every `ResetCeremonyView` the injected `CeremonyStage` caused the rings to build is found, `play` is called on it
/// exactly as the class documents for tests, and its own two layers are then posed at the instant the design
/// describes — the arc has arrived, the green ring is at full strength, the glint sits at the arc's end. Nothing is
/// drawn that the ceremony does not draw, and nothing at all appears in these images without the injection: with no
/// stage the rings build no ceremony view, and `CeremonySurfacesTests` proves that.
@MainActor
@Suite("Ceremony surface renders", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct CeremonySurfacesSnapshotTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)

    @Test("Every surface celebrating, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderCeremonies(language: LanguagePreference) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let code = language == .russian ? "ru" : "en"
        for surface in CeremonyScene.Surface.allCases {
            // A fresh scene per image: a surface that has celebrated has spent the ceremony.
            let scene = try CeremonyScene(language: language)
            try await render(scene: scene, surface: surface, name: "ceremony-\(surface.rawValue)-\(code)")
        }
        // The rail, whose ceremony already worked, for comparison with the three new ones.
        let scene = try CeremonyScene(language: language)
        try await renderRail(scene: scene, name: "ceremony-rail-\(code)")
    }

    @Test("The Presentation pane's Behavior section for both styles, in both languages", arguments: [LanguagePreference.english, .russian])
    func renderPresentationPane(language: LanguagePreference) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let code = language == .russian ? "ru" : "en"
        for style in PresentationStyle.allCases {
            for (width, suffix) in [(710.0 as CGFloat, ""), (550.0 as CGFloat, "-narrow")] {
                let scene = try CeremonyScene(language: language)
                scene.store.updateSettings { $0.appearance.presentationStyle = style }
                let name = "settings-presentation-\(style == .island ? "island" : "card")\(suffix)-\(code)"
                try await renderPane(store: scene.store, width: width, name: name)
            }
        }
    }

    // MARK: - Ceremony frames

    private func render(scene: CeremonyScene, surface: CeremonyScene.Surface, name: String) async throws {
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).first)
        let size = Self.canvas(for: surface)
        let content = scene.localized(Self.body(scene: scene, surface: surface))
            .frame(width: size.width, height: size.height)
            .background(Self.backdrop)
        try await capture(content, size: size, name: name) { host in
            let rings = CeremonyScene.ceremonyRings(in: host)
            #expect(!rings.isEmpty, "\(name) built no celebrating ring")
            for ring in rings {
                ring.play(ceremony)
                Self.pose(ring, fraction: scene.celebratingFraction)
            }
        }
    }

    private func renderRail(scene: CeremonyScene, name: String) async throws {
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .rail, now: UIFixture.now).first)
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        let size = CGSize(width: 320, height: 96)
        let content = scene.localized(RailView(store: scene.store, model: model, accounts: scene.store.visiblePresentations))
            .frame(width: size.width, height: size.height)
            .background(Self.backdrop)
        try await capture(content, size: size, name: name) { host in
            let rings = CeremonyScene.ceremonyRings(in: host)
            #expect(!rings.isEmpty, "\(name) built no celebrating ring")
            for ring in rings {
                ring.play(ceremony)
                Self.pose(ring, fraction: scene.celebratingFraction)
            }
        }
    }

    @ViewBuilder
    private static func body(scene: CeremonyScene, surface: CeremonyScene.Surface) -> some View {
        switch surface {
        case .deck, .popover:
            let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
            let _ = model.isExpanded = true
            let _ = model.selectedAccountID = scene.celebrating.id
            DeckContent(
                store: scene.store,
                model: model,
                accounts: scene.store.presentations,
                context: surface == .popover ? .popover : .island
            )
            .fixedSize()
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.86)))
        case .card, .pill:
            FloatingCardRootView(store: scene.store, model: scene.cardModel(expanded: surface == .card))
        }
    }

    private static func canvas(for surface: CeremonyScene.Surface) -> CGSize {
        switch surface {
        case .deck, .popover: CGSize(width: 460, height: 760)
        case .card, .pill: CGSize(width: 420, height: 340)
        }
    }

    /// The instant the design describes: the arc has arrived, the green ring is at full strength and has begun to
    /// swell, and the glint sits where the arc ends. The values are `ResetCeremonyPlan`'s own, on the layers the
    /// ceremony built for itself.
    private static func pose(_ ring: ResetCeremonyView, fraction: Double) {
        guard let layers = ring.layer?.sublayers else { return }
        let swell = 1 + (ResetCeremonyPlan.flashScale - 1) * 0.35
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.compactMap({ $0 as? CAShapeLayer }) {
            layer.removeAllAnimations()
            if layer.fillColor == nil {
                layer.opacity = 0.85
                layer.shadowOpacity = 0.6
                layer.transform = CATransform3DMakeScale(swell, swell, 1)
            } else {
                layer.opacity = 1
                // Layer space is y-up; a fraction of a turn clockwise from 12 o'clock is π/2 − f·2π.
                let angle = Double.pi / 2 - min(max(fraction, 0), 1) * 2 * .pi
                let center = CGPoint(x: ring.bounds.midX, y: ring.bounds.midY)
                layer.position = CGPoint(
                    x: center.x + ring.radius * CGFloat(cos(angle)),
                    y: center.y + ring.radius * CGFloat(sin(angle))
                )
            }
        }
        CATransaction.commit()
    }

    // MARK: - Settings pane

    private func renderPane(store: TrackerStore, width: CGFloat, name: String) async throws {
        let size = CGSize(width: width, height: 1_500)
        let content = SettingsPaneCaptureView(store: store, pane: .presentation)
            .frame(width: size.width, height: size.height)
        try await capture(content, size: size, name: name, appearance: NSAppearance(named: .aqua), settle: 12) { _ in }
    }

    // MARK: - Capture

    /// Hosts a view off screen, lets it settle, runs `prepare` (which poses the ceremony layers), and writes the PNG.
    /// The pose happens after the last layout: `LiveLayerView.layout` rebuilds its layers' geometry.
    private func capture(
        _ content: some View,
        size: CGSize,
        name: String,
        appearance: NSAppearance? = nil,
        settle: Int = 8,
        prepare: (NSView) -> Void
    ) async throws {
        let host = NSHostingView(rootView: AnyView(content))
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: NSSize(width: size.width, height: size.height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for _ in 0..<settle {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        prepare(host)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private static var backdrop: some View {
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.42, green: 0.18, blue: 0.30)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
