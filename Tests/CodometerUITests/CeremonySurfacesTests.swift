import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import QuartzCore
import SwiftUI
import Testing

/// Every surface that shows rings celebrates a limit reset, and each of them exactly once.
///
/// The rail already did; the deck, the menu bar popover and the floating card each inject their own `CeremonyStage`
/// now. Two things are checked, because the first alone is what was missing for a whole wave: the stage a surface
/// builds (a pure value), **and** that the stage actually reaches the rings — an `NSHostingView` builds the real view
/// tree and the test looks for the `ResetCeremonyView` the rings only create when the environment carries a stage for
/// their own surface. Without the injection there is no such view anywhere in the tree.
///
/// The ceremony itself is Core Animation and never plays here: an off-screen test window does not report
/// `occlusionState.contains(.visible)`, which is exactly the gate `ResetCeremonyView.playIfPossible` honours. The
/// animations are therefore started the way `ResetCeremonyView` documents for tests, by calling `play` directly.
@MainActor
@Suite("Ceremony surfaces")
struct CeremonySurfacesTests {
    // MARK: - The stage each surface builds

    @Test("The deck's stage celebrates on `.deck`, for the island's deck and for the popover")
    func deckStage() throws {
        let scene = try CeremonyScene(language: .english)
        let live = try #require(DeckContent.ceremonyStage(store: scene.store, context: .island, isExpanded: true, liveEffects: true))
        #expect(live.surface == .deck)
        #expect(live.now == UIFixture.now)

        // A popover's deck exists only while the popover is on screen, so it needs no expanded flag.
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .popover, isExpanded: false, liveEffects: true)?.surface == .deck)
        // A prewarmed island deck is built invisible before it unfolds: it must not spend the ceremony.
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .island, isExpanded: false, liveEffects: true) == nil)
        // Measurement copies and still renders run without live effects.
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .island, isExpanded: true, liveEffects: false) == nil)
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .popover, isExpanded: false, liveEffects: false) == nil)

        scene.store.updateSettings { $0.appearance.celebratesResets = false }
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .island, isExpanded: true, liveEffects: true) == nil)
        #expect(DeckContent.ceremonyStage(store: scene.store, context: .popover, isExpanded: false, liveEffects: true) == nil)
    }

    @Test("The card's stage celebrates on `.card` and follows the same two switches")
    func cardStage() throws {
        let scene = try CeremonyScene(language: .english)
        let live = try #require(FloatingCardRootView.ceremonyStage(store: scene.store, liveEffects: true))
        #expect(live.surface == .card)
        #expect(live.now == UIFixture.now)
        #expect(FloatingCardRootView.ceremonyStage(store: scene.store, liveEffects: false) == nil)

        scene.store.updateSettings { $0.appearance.celebratesResets = false }
        #expect(FloatingCardRootView.ceremonyStage(store: scene.store, liveEffects: true) == nil)
    }

    @Test("A stage lists only its own account's live resets, keyed the way a ring is")
    func stageCeremonies() throws {
        let scene = try CeremonyScene(language: .english)
        let stage = try #require(FloatingCardRootView.ceremonyStage(store: scene.store, liveEffects: true))
        let mine = stage.ceremonies(of: scene.celebrating.id)
        #expect(Array(mine.keys) == ["main/\(scene.resetWindowID)"])
        #expect(mine.values.first?.previousFraction == 0.88)
        #expect(stage.ceremonies(of: scene.quiet.id).isEmpty)
    }

    @Test("Rail, deck and card each get their own turn, and each of them only one")
    func onePlayPerSurface() throws {
        let scene = try CeremonyScene(language: .english)
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).first)

        func deckStage() throws -> CeremonyStage {
            try #require(DeckContent.ceremonyStage(store: scene.store, context: .island, isExpanded: true, liveEffects: true))
        }
        func cardStage() throws -> CeremonyStage {
            try #require(FloatingCardRootView.ceremonyStage(store: scene.store, liveEffects: true))
        }

        // The rail played it first: the deck and the card still owe the user their own celebration.
        scene.store.markCeremonyPlayed(ceremony.id, on: .rail)
        #expect(try deckStage().ceremonies(of: scene.celebrating.id).count == 1)
        #expect(try cardStage().ceremonies(of: scene.celebrating.id).count == 1)

        try deckStage().markPlayed(ceremony.id, .deck)
        #expect(try deckStage().ceremonies(of: scene.celebrating.id).isEmpty)
        #expect(try cardStage().ceremonies(of: scene.celebrating.id).count == 1)

        try cardStage().markPlayed(ceremony.id, .card)
        #expect(try cardStage().ceremonies(of: scene.celebrating.id).isEmpty)
        #expect(scene.store.ceremonies.unplayed(on: .popover, now: UIFixture.now).count == 1)

        // And nothing celebrates a reset that has outlived its 60 s.
        let late = try #require(DeckContent.ceremonyStage(
            store: CeremonyScene(language: .english, age: ResetCeremony.lifetime).store,
            context: .island,
            isExpanded: true,
            liveEffects: true
        ))
        #expect(late.ceremonies(of: scene.celebrating.id).isEmpty)
    }

    // MARK: - The stage reaching the rings

    @Test(
        "Deck, popover, card and pill each build a celebrating ring, in both languages",
        arguments: [LanguagePreference.english, .russian]
    )
    func everySurfaceCelebrates(language: LanguagePreference) throws {
        let scene = try CeremonyScene(language: language)
        for surface in CeremonyScene.Surface.allCases {
            #expect(scene.ceremonyRings(on: surface).count == 1, "\(surface) did not celebrate in \(language.rawValue)")
        }
        // The control: the rail, which already worked, and which is a different `CeremonySurface`.
        #expect(scene.railCeremonyRings().count == 1)
    }

    @Test("No ring celebrates with \"Celebrate limit resets\" off, or on a deck that is only prewarmed")
    func nothingCelebratesWhenItMustNot() throws {
        let scene = try CeremonyScene(language: .english)
        // A deck built for the open that is about to happen is invisible: spending the ceremony there would show it
        // to nobody and leave the unfolded deck blank.
        #expect(scene.ceremonyRings(on: .deck, expanded: false).isEmpty)

        scene.store.updateSettings { $0.appearance.celebratesResets = false }
        for surface in CeremonyScene.Surface.allCases {
            #expect(scene.ceremonyRings(on: surface).isEmpty, "\(surface) celebrated with the setting off")
        }
        #expect(scene.railCeremonyRings().isEmpty)
    }

    @Test("A deck ring reports the play back to the store as `.deck`, leaving the other surfaces theirs")
    func playingMarksOnlyThisSurface() throws {
        let scene = try CeremonyScene(language: .english)
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).first)
        let ring = try #require(scene.ceremonyRings(on: .deck).first)

        // What `ResetCeremonyView` calls once it has played; the surface comes from the injected stage.
        let report = try #require(ring.onPlayed)
        report(ceremony.id)
        #expect(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).isEmpty)
        #expect(scene.store.ceremonies.unplayed(on: .card, now: UIFixture.now).count == 1)
        #expect(scene.store.ceremonies.unplayed(on: .rail, now: UIFixture.now).count == 1)
    }

    @Test("The card's ring reports its play as `.card`")
    func cardPlayMarksTheCard() throws {
        let scene = try CeremonyScene(language: .english)
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .card, now: UIFixture.now).first)
        let ring = try #require(scene.ceremonyRings(on: .card).first)
        let report = try #require(ring.onPlayed)
        report(ceremony.id)
        #expect(scene.store.ceremonies.unplayed(on: .card, now: UIFixture.now).isEmpty)
        #expect(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).count == 1)
    }

    @Test("A ring the deck built runs the glint and the flash of the ceremony plan", arguments: CeremonyScene.Surface.allCases)
    func ringPlaysTheWholeCeremony(surface: CeremonyScene.Surface) throws {
        let scene = try CeremonyScene(language: .english)
        let ceremony = try #require(scene.store.ceremonies.unplayed(on: .deck, now: UIFixture.now).first)
        let ring = try #require(scene.ceremonyRings(on: surface).first)
        // An off-screen window never reports `.visible` here, so the play gate is bypassed the documented way.
        ring.play(ceremony)

        let layers = try #require(ring.layer?.sublayers) as [CALayer]
        let flash = try #require(layers.first { ($0 as? CAShapeLayer)?.fillColor == nil })

        // A Mac with Reduce Motion on (build machines often have it) plays the reduced plan: the green ring only
        // fades, and there is no glint to ride the arc.
        if ring.reduceMotion {
            #expect(layers.first { ($0 as? CAShapeLayer)?.fillColor != nil } == nil)
            let fade = try #require(flash.animation(forKey: "flash") as? CABasicAnimation)
            #expect(fade.keyPath == "opacity")
            #expect(fade.duration == ResetCeremonyPlan.reducedDuration)
            return
        }

        let glint = try #require(layers.first { ($0 as? CAShapeLayer)?.fillColor != nil })

        let flashGroup = try #require(flash.animation(forKey: "flash") as? CAAnimationGroup)
        #expect(flashGroup.duration == ResetCeremonyPlan.flashDuration)
        #expect(flashGroup.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath }.sorted()
            == ["opacity", "shadowOpacity", "transform.scale"])
        // The flash must not fill backwards: a green halo for the whole unwind is the defect this guards against.
        #expect(flashGroup.fillMode == .removed)
        #expect(flash.opacity == 0)

        let glintGroup = try #require(glint.animation(forKey: "glint") as? CAAnimationGroup)
        #expect(glintGroup.duration == ResetCeremonyPlan.glintDuration)
        // The flash starts while the arc is still settling, so the whole thing lasts about the 1.25 s of the design.
        #expect(abs(flashGroup.beginTime - glintGroup.beginTime - ResetCeremonyPlan.flashDelay) < 0.001)
        #expect(ResetCeremonyPlan.total == ResetCeremonyPlan.flashDelay + ResetCeremonyPlan.flashDuration)
    }

    @Test("A ceremony changes no surface's size, in either language", arguments: [LanguagePreference.english, .russian])
    func ceremonyChangesNoSize(language: LanguagePreference) throws {
        let celebrating = try CeremonyScene(language: language)
        let still = try CeremonyScene(language: language)
        still.store.updateSettings { $0.appearance.celebratesResets = false }
        #expect(!celebrating.ceremonyRings(on: .deck).isEmpty && still.ceremonyRings(on: .deck).isEmpty)

        // The ceremony draws inside the ring's own square (`RingStack` puts it in the stack under the dial's frame),
        // so nothing it adds may move a single point of any surface.
        for surface in CeremonyScene.Surface.allCases {
            #expect(
                celebrating.fittingSize(of: surface) == still.fittingSize(of: surface),
                "\(surface) resized while celebrating in \(language.rawValue)"
            )
        }
        #expect(celebrating.railFittingSize() == still.railFittingSize())
    }

    @Test("Neither language makes a surface a different size, celebrating or not")
    func languagesAgreeOnSize() throws {
        let english = try CeremonyScene(language: .english)
        let russian = try CeremonyScene(language: .russian)
        // The card and its pill reserve the widest template of *every* language (`CardPillTemplates.everyLanguage`),
        // which is what keeps a `language` step from resizing the window.
        for surface in [CeremonyScene.Surface.card, .pill] {
            #expect(english.fittingSize(of: surface) == russian.fittingSize(of: surface), "\(surface) differs between EN and RU")
        }
        // The deck and the rail are fixed-width by `IslandMetrics`; their height must not move either.
        #expect(english.fittingSize(of: .deck).width == russian.fittingSize(of: .deck).width)
        #expect(english.railFittingSize() == russian.railFittingSize())
    }

    @Test("A celebrating dial says so out loud, in both languages", arguments: [LanguagePreference.english, .russian])
    func voiceOverSaysJustReset(language: LanguagePreference) throws {
        let scene = try CeremonyScene(language: language)
        let l10n = scene.store.localizer
        let presentation = try #require(scene.store.presentations.first { $0.id == scene.celebrating.id })
        let quiet = RingGauge.accessibilityDetails(presentation: presentation, celebrates: false, l10n: l10n)
        let celebrating = RingGauge.accessibilityDetails(presentation: presentation, celebrates: true, l10n: l10n)
        #expect(celebrating == quiet + [l10n.motion.justResetA11y])
        #expect(!l10n.motion.justResetA11y.isEmpty)
    }
}

/// One store with a live reset on its first account, and the four surfaces that have to celebrate it.
@MainActor
struct CeremonyScene {
    /// The ring-carrying surfaces the environment injection had to reach. The rail already had its own and is used
    /// as the control, so it is not in this list.
    enum Surface: String, CaseIterable, CustomStringConvertible {
        case deck
        case popover
        case card
        case pill

        var description: String { rawValue }
    }

    let store: TrackerStore
    let celebrating: AccountProfile
    let quiet: AccountProfile
    let resetWindowID: String
    /// Where the celebrating account's arc ends after the reset, as a fraction of a turn.
    let celebratingFraction: Double

    /// - Parameter age: How long ago the reset was detected; the default is right now, `ResetCeremony.lifetime`
    ///   is already too late to celebrate.
    init(language: LanguagePreference, age: TimeInterval = 0) throws {
        let tints: [AccountTint] = [.teal, .pink]
        var profiles: [AccountProfile] = []
        var statuses: [AccountStatus] = []
        for (index, label) in ["Work", "Personal"].enumerated() {
            let profile = try AccountProfile(
                provider: .claude,
                label: try AccountLabel(validating: label),
                directory: try ProfileDirectory(validating: "/Users/example/.ceremony-\(index)"),
                tint: tints[index],
                monogram: try AccountMonogram(validating: String(label.prefix(1)))
            )
            profiles.append(profile)
            statuses.append(AccountStatus(
                profile: profile,
                identity: AccountIdentity(email: "user\(index)@example.com", organization: nil, plan: "max_20x"),
                reading: try UIFixture.reading([try UIFixture.bucket("main", [
                    // The first account has just reset: its session ring sits near empty again.
                    try UIFixture.window("session", .session, used: index == 0 ? 4 : 47, duration: .fiveHours, resetsIn: 5 * 3_600),
                    try UIFixture.window("week", .weekly(model: nil), used: 61 - Double(index) * 12, duration: .oneWeek, resetsIn: 4 * 86_400),
                ])]),
                sessions: []
            ))
        }
        var settings = try AppSettings(accounts: profiles)
        settings.general.language = language
        let store = TrackerStore(
            state: TrackerState(accounts: statuses),
            settings: settings,
            now: UIFixture.now,
            actions: UIFixture.actions(),
            region: { Locale(identifier: language == .russian ? "ru_RU" : "en_US") }
        )
        store.refreshLocale()

        self.store = store
        celebrating = profiles[0]
        quiet = profiles[1]
        resetWindowID = "session"
        celebratingFraction = 0.04
        let event = try WindowResetEvent(
            accountID: celebrating.id,
            bucketID: "main",
            windowID: resetWindowID,
            previousUsed: try Percentage(validating: 88),
            newUsed: try Percentage(validating: 4),
            detectedAt: UIFixture.now.addingTimeInterval(-age)
        )
        store.celebrate([event], now: UIFixture.now.addingTimeInterval(-age))
    }

    /// The `ResetCeremonyView`s a real, laid-out surface builds. A hosting view instantiates the representables
    /// during layout, so no window (and no on-screen anything) is needed to see what the rings did with the stage.
    func ceremonyRings(on surface: Surface, expanded: Bool = true) -> [ResetCeremonyView] {
        Self.ceremonyRings(in: view(for: surface, expanded: expanded), size: Self.canvas(for: surface))
    }

    /// The rail's, for comparison: a different `CeremonySurface` with its own stage, which already worked.
    func railCeremonyRings() -> [ResetCeremonyView] {
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        return Self.ceremonyRings(
            in: AnyView(localized(RailView(store: store, model: model, accounts: store.visiblePresentations))),
            size: CGSize(width: 320, height: 80)
        )
    }

    // MARK: - Surfaces

    private func view(for surface: Surface, expanded: Bool) -> AnyView {
        switch surface {
        case .deck, .popover:
            let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
            model.isExpanded = expanded
            model.selectedAccountID = celebrating.id
            return AnyView(localized(DeckContent(
                store: store,
                model: model,
                accounts: store.presentations,
                context: surface == .popover ? .popover : .island
            )))
        case .card, .pill:
            return AnyView(localized(FloatingCardRootView(store: store, model: cardModel(expanded: surface == .card))))
        }
    }

    private static func canvas(for surface: Surface) -> CGSize {
        switch surface {
        case .deck, .popover: CGSize(width: 460, height: 760)
        case .card, .pill: CGSize(width: 420, height: 360)
        }
    }

    func cardModel(expanded: Bool) -> FloatingCardModel {
        let metrics = CardMetrics(store.settings.appearance.scale)
        let model = FloatingCardModel()
        model.metrics = metrics
        model.size = .regular
        model.anchor = .topTrailing
        model.thirdTile = store.settings.appearance.floatingCard.thirdTile
        model.isExpanded = expanded
        model.theme = CardThemeTokens.resolve(theme: .graphite, scheme: .dark, reducesTransparency: false, increasesContrast: false)
        model.selectedAccountID = celebrating.id
        let card = CGRect(origin: CGPoint(x: metrics.windowMargin, y: metrics.windowMargin), size: metrics.cardSize(.regular))
        let pill = metrics.pillSize(accounts: store.visiblePresentations.count, templates: CardPillTemplates.everyLanguage)
        model.cardFrame = card
        model.pillFrame = CGRect(x: card.maxX - pill.width, y: card.minY, width: pill.width, height: pill.height)
        return model
    }

    /// The words and the region the surface is measured and read in. Live effects stay on: without them no ring
    /// celebrates anywhere, which is the point of the check.
    func localized(_ view: some View) -> some View {
        view
            .environment(\.l10n, store.localizer)
            .environment(\.locale, store.localizer.locale)
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Measurement

    /// What the surface asks for, laid out exactly as the checks host it.
    func fittingSize(of surface: Surface, expanded: Bool = true) -> CGSize {
        NSHostingView(rootView: view(for: surface, expanded: expanded)).fittingSize
    }

    func railFittingSize() -> CGSize {
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        return NSHostingView(
            rootView: AnyView(localized(RailView(store: store, model: model, accounts: store.visiblePresentations)))
        ).fittingSize
    }

    // MARK: - View tree

    static func ceremonyRings(in view: AnyView, size: CGSize) -> [ResetCeremonyView] {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return ceremonyRings(in: host)
    }

    /// The `ResetCeremonyView`s below a view that is already hosted and laid out.
    static func ceremonyRings(in view: NSView) -> [ResetCeremonyView] {
        var found: [ResetCeremonyView] = []
        collect(view, into: &found)
        return found
    }

    private static func collect(_ view: NSView, into found: inout [ResetCeremonyView]) {
        if let ceremony = view as? ResetCeremonyView { found.append(ceremony) }
        for subview in view.subviews { collect(subview, into: &found) }
    }
}
