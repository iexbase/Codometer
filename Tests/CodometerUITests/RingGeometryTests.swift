import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import CoreGraphics
import QuartzCore
import Foundation
import SwiftUI
import Testing

/// The ring grammar's new parts: which forecasts become a ghost arc, which ring celebrates a reset, and how the rail
/// marks accounts that share a provider.
@MainActor
@Suite("Ring grammar")
struct RingGeometryTests {
    private static let now = UIFixture.now
    private static let thresholds = BandThresholds.standard

    /// A five-hour window `used` per cent through, with `elapsed` of it gone.
    private static func window(_ id: String, used: Double, elapsed: Double) throws -> LimitWindow {
        let length = WindowDuration.fiveHours.timeInterval
        return try UIFixture.window(id, .session, used: used, duration: .fiveHours, resetsIn: length * (1 - elapsed))
    }

    private static func forecast(used: Double, elapsed: Double) throws -> UsageForecast? {
        UsageForecast(window: try window("w", used: used, elapsed: elapsed), now: now, thresholds: thresholds)
    }


    // MARK: Forecast policy

    @Test("Only a forecast that runs into the limit reaches a small dial")
    func policies() throws {
        let calm = try #require(try Self.forecast(used: 40, elapsed: 0.5))
        let reaching = try #require(try Self.forecast(used: 60, elapsed: 0.4))
        #expect(!calm.reachesLimit && abs(calm.projectedUsed - 80) < 0.001)
        #expect(reaching.reachesLimit && abs(reaching.projectedUsed - 150) < 0.001)

        #expect(RingForecastPolicy.always.draws(calm))
        #expect(RingForecastPolicy.always.draws(reaching))
        #expect(!RingForecastPolicy.warningsOnly.draws(calm))
        #expect(RingForecastPolicy.warningsOnly.draws(reaching))
        #expect(!RingForecastPolicy.never.draws(calm))
        #expect(!RingForecastPolicy.never.draws(reaching))
        for policy in [RingForecastPolicy.never, .warningsOnly, .always] {
            #expect(!policy.draws(nil))
            #expect(policy.arcEnd(used: 0.4, forecast: nil) == nil)
        }
    }

    @Test("The ghost ends at the projection, never laps its own start, and never goes backwards")
    func arcEnd() throws {
        let calm = try #require(try Self.forecast(used: 40, elapsed: 0.5))
        let reaching = try #require(try Self.forecast(used: 60, elapsed: 0.4))
        #expect(RingForecastPolicy.always.arcEnd(used: 0.4, forecast: calm) == 0.8)
        // 150 % would wrap past the start, so it stops just short of a full turn.
        #expect(RingForecastPolicy.always.arcEnd(used: 0.6, forecast: reaching) == RingForecastPolicy.maximumArcEnd)
        // A ring already past its own projection shows nothing.
        #expect(RingForecastPolicy.always.arcEnd(used: 0.95, forecast: calm) == nil)
    }

    // MARK: Specs

    /// Claude's three headline windows: a session ring that will run out, a calm week and a model week.
    private func presentation(showsForecast: Bool = true, stale: Bool = false) throws -> AccountPresentation {
        var appearance = AppearanceSettings()
        appearance.showsForecast = showsForecast
        let main = try UIFixture.bucket("claude", [
            try Self.window("session", used: 60, elapsed: 0.4),
            try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek, resetsIn: 4 * 86_400),
            try UIFixture.window("week.opus", .weekly(model: "Opus"), used: 63, duration: .oneWeek, resetsIn: 4 * 86_400),
        ])
        let other = try UIFixture.bucket("spark", title: "Spark", [try UIFixture.window("primary", used: 12)])
        let status = AccountStatus(
            profile: try UIFixture.profile("Work"),
            reading: try UIFixture.reading([main, other], capturedAgo: stale ? 3 * 3_600 : 60)
        )
        return AccountPresentation(status: status, appearance: appearance, now: Self.now, l10n: .testEnglish)
    }

    @Test("A rail dial shows only the reaching forecast; a deck dial shows every one")
    func specsByPolicy() throws {
        let account = try presentation()
        let rail = RingGeometry.specs(
            headline: account.headline,
            windows: account.windows,
            maximumRings: 1,
            diameter: 28,
            forecastPolicy: .warningsOnly
        )
        #expect(rail.count == 1)
        #expect(rail[0].forecast == RingForecastPolicy.maximumArcEnd)

        let deck = RingGeometry.specs(
            headline: account.headline,
            windows: account.windows,
            maximumRings: 3,
            diameter: 58,
            forecastPolicy: .always
        )
        #expect(deck.count == 3)
        // The session ring runs into the limit; the weekly ring lands calmly short of it.
        #expect(deck[0].forecast == RingForecastPolicy.maximumArcEnd && deck[0].forecastBand == .exhausted)
        let weekly = try #require(deck[1].forecast)
        #expect(weekly > deck[1].progress.used && weekly < RingForecastPolicy.maximumArcEnd)
        #expect(deck[1].forecastBand != nil)

        let settings = RingGeometry.specs(headline: account.headline, windows: account.windows, maximumRings: 1, diameter: 46)
        #expect(settings.allSatisfy { $0.forecast == nil })
    }

    @Test("Turning the forecast off removes it from every ring")
    func forecastSetting() throws {
        let account = try presentation(showsForecast: false)
        let specs = RingGeometry.specs(
            headline: account.headline,
            windows: account.windows,
            maximumRings: 3,
            diameter: 58,
            forecastPolicy: .always
        )
        #expect(specs.allSatisfy { $0.forecast == nil })
    }

    // MARK: Ceremonies

    private func ceremony(bucketID: String, windowID: String, previous: Double = 0.64) throws -> ResetCeremony {
        let event = try WindowResetEvent(
            accountID: AccountID(),
            bucketID: bucketID,
            windowID: windowID,
            previousUsed: try Percentage(validating: previous * 100),
            newUsed: try Percentage(validating: 3),
            detectedAt: Self.now
        )
        return ResetCeremony(event: event, previousFraction: previous, startedAt: Self.now)
    }

    @Test("A ceremony lands on the ring whose window reset, and nowhere else")
    func ceremonyAttachment() throws {
        let account = try presentation()
        let specs = RingGeometry.specs(
            headline: account.headline,
            windows: account.windows,
            maximumRings: 3,
            diameter: 58,
            forecastPolicy: .always,
            ceremonies: [
                "claude/week": try ceremony(bucketID: "claude", windowID: "week"),
                // Another bucket's window is not on these rings at all.
                "spark/primary": try ceremony(bucketID: "spark", windowID: "primary"),
            ]
        )
        #expect(specs.map { $0.ceremony != nil } == [false, true, false])
        #expect(specs[1].ceremony?.event.windowID == "week")
    }

    @Test("A stage hands a surface only its own unplayed ceremonies, and only while they are alive")
    func stage() throws {
        let account = AccountID()
        let event = try WindowResetEvent(
            accountID: account,
            bucketID: "claude",
            windowID: "session",
            previousUsed: try Percentage(validating: 64),
            newUsed: try Percentage(validating: 3),
            detectedAt: Self.now
        )
        var board = CeremonyBoard()
        board.insert([event], previousFractions: [:], now: Self.now)
        let stage = CeremonyStage(surface: .rail, board: board, now: Self.now) { _, _ in }
        #expect(stage.ceremonies(of: account).keys.sorted() == ["claude/session"])
        #expect(stage.ceremonies(of: AccountID()).isEmpty)

        var played = board
        let id = try #require(board.unplayed(on: .rail, now: Self.now).first?.id)
        played.markPlayed(id, on: .rail)
        #expect(CeremonyStage(surface: .rail, board: played, now: Self.now) { _, _ in }.ceremonies(of: account).isEmpty)
        // Another surface has not played it yet.
        #expect(!CeremonyStage(surface: .deck, board: played, now: Self.now) { _, _ in }.ceremonies(of: account).isEmpty)
        // And it expires on its own.
        let late = Self.now.addingTimeInterval(ResetCeremony.lifetime + 1)
        #expect(CeremonyStage(surface: .rail, board: board, now: late) { _, _ in }.ceremonies(of: account).isEmpty)
    }

    @Test("The sheen skips a rail label whose account is celebrating, however its number changed")
    func sheenSuppression() {
        let quiet: [RailLabel] = [.percent("64%", value: 64), .percent("12%", value: 12)]
        let afterReset: [RailLabel] = [.percent("3%", value: 3), .percent("12%", value: 12)]
        let before = RailView.sheenTrigger(labels: quiet)
        #expect(RailView.sheenTrigger(labels: afterReset) != before)
        // With the ceremony playing, the same change leaves the trigger alone.
        #expect(RailView.sheenTrigger(labels: quiet, celebrating: [0]) == RailView.sheenTrigger(labels: afterReset, celebrating: [0]))
        // The other account's label still counts.
        let otherChanged: [RailLabel] = [.percent("3%", value: 3), .percent("13%", value: 13)]
        #expect(RailView.sheenTrigger(labels: otherChanged, celebrating: [0]) != RailView.sheenTrigger(labels: afterReset, celebrating: [0]))
    }

    @Test("Which accounts are celebrating is read off the board, in the rail's own order")
    func celebratingIndices() throws {
        let profiles = [try UIFixture.profile("Work"), try UIFixture.profile("Personal")]
        let presentations = try profiles.map { profile in
            AccountPresentation(
                status: AccountStatus(profile: profile, reading: try UIFixture.reading([try UIFixture.bucket("claude", [try UIFixture.window("session", used: 3)])])),
                appearance: AppearanceSettings(),
                now: Self.now,
                l10n: .testEnglish
            )
        }
        var board = CeremonyBoard()
        board.insert(
            [try WindowResetEvent(
                accountID: profiles[1].id,
                bucketID: "claude",
                windowID: "session",
                previousUsed: try Percentage(validating: 64),
                newUsed: try Percentage(validating: 3),
                detectedAt: Self.now
            )],
            previousFractions: [:],
            now: Self.now
        )
        let stage = CeremonyStage(surface: .rail, board: board, now: Self.now) { _, _ in }
        #expect(RailView.celebratingIndices(accounts: presentations, stage: stage) == [1])
        #expect(RailView.celebratingIndices(accounts: presentations, stage: nil).isEmpty)
    }

    @Test("A ceremony puts exactly two one-shot animations on the render server")
    func ceremonyAnimations() throws {
        let side: CGFloat = 60
        let view = ResetCeremonyView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.update(
            ceremony: try ceremony(bucketID: "claude", windowID: "session"),
            ring: RingGeometry(diameter: side, count: 1).rings[0],
            fraction: 0.03,
            delay: 0,
            reduceMotion: false
        )
        view.layout()
        view.play(try ceremony(bucketID: "claude", windowID: "session"))
        let layers = try #require(view.layer?.sublayers)
        #expect(layers.count == 2, "a flash ring and a glint, nothing more")
        let flash = try #require(layers.first { $0.animation(forKey: "flash") != nil })
        let glint = try #require(layers.first { $0.animation(forKey: "glint") != nil })
        let flashGroup = try #require(flash.animation(forKey: "flash") as? CAAnimationGroup)
        #expect(flashGroup.duration == ResetCeremonyPlan.flashDuration)
        #expect(flashGroup.animations?.count == 3, "swell, fade and bloom")
        let glintGroup = try #require(glint.animation(forKey: "glint") as? CAAnimationGroup)
        #expect(glintGroup.duration == ResetCeremonyPlan.glintDuration)
        // The glint rides a real arc from the old fraction to the new one.
        let ride = try #require(glintGroup.animations?.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == "position" })
        #expect(ride.path != nil)
        #expect(ride.calculationMode == .paced)
        // The flash lands while the arc is settling, and the whole thing is about 1.25 s.
        #expect(abs(flashGroup.beginTime - glintGroup.beginTime - ResetCeremonyPlan.flashDelay) < 0.001)
        #expect(ResetCeremonyPlan.total > 1.2 && ResetCeremonyPlan.total < 1.3)
        // Nothing repeats: a ceremony happens once.
        #expect(flashGroup.repeatCount == 0 && glintGroup.repeatCount == 0)
    }

    @Test("The green ring is invisible until it flashes, and gone again afterwards")
    func ceremonyFlashIsNotAHalo() throws {
        let side: CGFloat = 60
        let view = ResetCeremonyView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let event = try ceremony(bucketID: "claude", windowID: "session")
        view.update(ceremony: event, ring: RingGeometry(diameter: side, count: 1).rings[0], fraction: 0.03, delay: 0, reduceMotion: false)
        view.layout()
        view.play(event)
        let layers = try #require(view.layer?.sublayers)
        let flash = try #require(layers.first { $0.animation(forKey: "flash") != nil })
        let group = try #require(flash.animation(forKey: "flash") as? CAAnimationGroup)
        // It begins three quarters of a second after the unwind starts…
        #expect(group.beginTime > CACurrentMediaTime() + ResetCeremonyPlan.flashDelay - 0.05)
        // …so a backwards fill would show the ring at full opacity for that whole time. Only the layer's own
        // transparency may show before and after.
        #expect(group.fillMode == .removed, "the flash would sit on the dial as a green halo")
        #expect(group.isRemovedOnCompletion)
        #expect(flash.opacity == 0)
        #expect(flash.shadowOpacity == 0)
    }

    @Test("Reduce Motion keeps the green ring and drops every movement")
    func ceremonyReducedMotion() throws {
        let side: CGFloat = 60
        let view = ResetCeremonyView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let event = try ceremony(bucketID: "claude", windowID: "session")
        view.update(ceremony: event, ring: RingGeometry(diameter: side, count: 1).rings[0], fraction: 0.03, delay: 0, reduceMotion: true)
        view.layout()
        view.play(event)
        let layers = try #require(view.layer?.sublayers)
        #expect(layers.count == 1, "only the green ring")
        let fade = try #require(layers[0].animation(forKey: "flash") as? CABasicAnimation)
        #expect(fade.keyPath == "opacity")
        #expect(fade.duration == ResetCeremonyPlan.reducedDuration)
    }

    // MARK: Rail identity

    @Test("The rail marks identity only when two tracked accounts share a provider")
    func identityMarks() throws {
        let claude = try UIFixture.profile("Work")
        let codex = try UIFixture.profile("Side", provider: .codex)
        let secondClaude = try UIFixture.profile("Personal")
        let disabledClaude = try UIFixture.profile("Old", isEnabled: false)
        #expect(!RailView.showsIdentityMarks(accounts: []))
        #expect(!RailView.showsIdentityMarks(accounts: [claude]))
        #expect(!RailView.showsIdentityMarks(accounts: [claude, codex]))
        #expect(RailView.showsIdentityMarks(accounts: [claude, secondClaude]))
        // An account that is not tracked does not make the rail change its shape.
        #expect(!RailView.showsIdentityMarks(accounts: [claude, disabledClaude, codex]))
        // Only the doubled provider gives up its glyph; the lone Codex account keeps its mark.
        #expect(RailView.sharedProviders(accounts: [claude, secondClaude, codex]) == [.claude])
        #expect(RailView.sharedProviders(accounts: [claude, codex]).isEmpty)
    }

    @Test("A dial's centre shows one character of the monogram")
    func centerInitial() throws {
        #expect(RingCenter.initial(of: try AccountMonogram(validating: "wa")) == "W")
        #expect(RingCenter.initial(of: try AccountMonogram(validating: "Л")) == "Л")
        #expect(RingCenter.initial(of: try AccountMonogram(validating: "🚀")) == "🚀")
        #expect(RingCenter.initial(of: try AccountMonogram(validating: "7")) == "7")
    }

    @Test("The identity dots stay small marks at every island scale", arguments: [0.75, 1.0, 1.5])
    func dotSizes(scale: Double) {
        let metrics = IslandMetrics(scale: CGFloat(scale))
        #expect(RailView.identityDotSize(metrics: metrics) >= 3)
        #expect(RailView.identityDotSize(metrics: metrics) <= metrics.railDial / 4)
        #expect(DeckDial.identityDotSize(metrics) >= 4)
        #expect(DeckDial.identityDotSize(metrics) <= metrics.deckDial / 4)
    }

    // MARK: Accessibility

    @Test("A drawn forecast is always spoken, and the phrases match the language", arguments: [LanguagePreference.english, .russian])
    func forecastPhrase(language: LanguagePreference) throws {
        let l10n: Localizer = language == .russian ? .testRussian : .testEnglish
        let account = try presentation()
        let spoken = try #require(RingGauge.forecastPhrase(presentation: account, forecastPolicy: .always, l10n: l10n))
        #expect(spoken == l10n.motion.forecastRunsOutA11y)
        // A dial that draws no ghost says nothing about one.
        #expect(RingGauge.forecastPhrase(presentation: account, forecastPolicy: .never, l10n: l10n) == nil)
        #expect(RingGauge.forecastPhrase(presentation: try presentation(showsForecast: false), forecastPolicy: .always, l10n: l10n) == nil)
    }

    @Test("A calm forecast is spoken with its projected number")
    func calmForecastPhrase() throws {
        var appearance = AppearanceSettings()
        appearance.showsForecast = true
        let bucket = try UIFixture.bucket("claude", [try Self.window("session", used: 40, elapsed: 0.5)])
        let account = AccountPresentation(
            status: AccountStatus(profile: try UIFixture.profile("Work"), reading: try UIFixture.reading([bucket])),
            appearance: appearance,
            now: Self.now,
            l10n: .testEnglish
        )
        let spoken = try #require(RingGauge.forecastPhrase(presentation: account, forecastPolicy: .always, l10n: .testEnglish))
        #expect(spoken == "at this pace about 80% by reset")
        let russian = try #require(RingGauge.forecastPhrase(presentation: account, forecastPolicy: .always, l10n: .testRussian))
        #expect(russian.contains("80"))
        #expect(russian == Localizer.testRussian.motion.forecastA11y(Localizer.testRussian.format.percent(80)))
    }

    @Test("A celebrating dial says so, so the green flash is never the only signal")
    func ceremonyPhrase() throws {
        let account = try presentation()
        let details = RingGauge.accessibilityDetails(presentation: account, forecastPolicy: .always, celebrates: true, l10n: .testEnglish)
        #expect(details.contains("just reset"))
        let quiet = RingGauge.accessibilityDetails(presentation: account, forecastPolicy: .always, celebrates: false, l10n: .testEnglish)
        #expect(!quiet.contains("just reset"))
        #expect(Localizer.testRussian.motion.justResetA11y == "только что сброшен")
    }

    @Test("A stale dial speaks no forecast, because it draws none")
    func staleSaysNothing() throws {
        let account = try presentation(stale: true)
        #expect(account.isStale)
        let details = RailView.dialAccessibilityValue(presentation: account, now: Self.now, forecastPolicy: .always, l10n: .testEnglish)
        #expect(!details.contains("pace"))
    }
}

/// The rail's clickable chrome, measured the way a pointer meets it.
@MainActor
@Suite("Rail hit targets")
struct RailHitTargetTests {
    @Test("The waiting tab is a 24 pt target at every island scale", arguments: [0.75, 1.0, 1.5])
    func attentionTab(scale: Double) {
        _ = NSApplication.shared
        let metrics = IslandMetrics(scale: CGFloat(scale))
        let host = NSHostingView(rootView: AttentionTab(count: 1, metrics: metrics) {}.environment(\.l10n, .testEnglish))
        let size = host.fittingSize
        #expect(size.height >= 24, "\(size.height) pt tall at scale \(scale)")
        #expect(size.width >= 24, "\(size.width) pt wide at scale \(scale)")
        // And it never becomes so big that it drives the rail's height instead of the dials.
        #expect(size.height < metrics.railDial + 2 * metrics.orbitMargin)
    }

    @Test("A two-digit queue only widens the tab, it never makes it taller")
    func countDoesNotChangeHeight() {
        _ = NSApplication.shared
        let metrics = IslandMetrics(scale: 1)
        let heights = [1, 12, 99].map { count in
            NSHostingView(rootView: AttentionTab(count: count, metrics: metrics) {}.environment(\.l10n, .testEnglish)).fittingSize.height
        }
        #expect(Set(heights).count == 1, "\(heights)")
    }
}

@Suite("Ring geometry, measured")
struct RingMeasurementTests {
    @Test("Capacity follows the diameter")
    func capacity() {
        #expect(RingGeometry.capacity(diameter: 28) == 1)
        #expect(RingGeometry.capacity(diameter: 34) == 2)
        #expect(RingGeometry.capacity(diameter: 42) == 3)
        #expect(RingGeometry(diameter: 28, count: 3).rings.count == 1)
    }

    @Test("Concentric rings never overlap and leave room for the glyph", arguments: [42.0, 49.3, 58.0, 87.0, 116.0])
    func concentric(diameter: Double) {
        let geometry = RingGeometry(diameter: diameter, count: 3)
        #expect(geometry.rings.count == 3)
        let outer = geometry.rings[0]
        #expect(abs(outer.radius + outer.lineWidth / 2 - diameter / 2) < 0.001)
        for (outside, inside) in zip(geometry.rings, geometry.rings.dropFirst()) {
            #expect(inside.radius + inside.lineWidth / 2 + geometry.gap <= outside.radius - outside.lineWidth / 2 + 0.001)
            #expect(inside.lineWidth <= outside.lineWidth)
        }
        #expect(geometry.innerRadius >= diameter * 0.15)
    }

    @Test("Notch, overrun and ticks")
    func grammar() {
        #expect(!RingGeometry.showsNotch(elapsed: nil))
        #expect(!RingGeometry.showsNotch(elapsed: 0.005))
        #expect(RingGeometry.showsNotch(elapsed: 0.4))
        #expect(!RingGeometry.showsNotch(elapsed: 0.995))
        #expect(RingGeometry.overrunRange(used: 0.63, elapsed: 0.41) == 0.41...0.63)
        #expect(RingGeometry.overrunRange(used: 0.3, elapsed: 0.41) == nil)
        #expect(RingGeometry.overrunRange(used: 0.7, elapsed: nil) == nil)
        #expect(RingGeometry.overrunRange(used: 1.4, elapsed: 0.5) == 0.5...1)
        #expect(RingGeometry.tickFractions(count: 7).count == 6)
        #expect(RingGeometry.tickFractions(count: 7).first == 1.0 / 7)
        #expect(RingGeometry.tickFractions(count: 5).isEmpty)
        #expect(RingGeometry.tickFractions(count: 0).isEmpty)
        #expect(RingGeometry.notchWidth(lineWidth: 2) == 1.25)
        let top = RingGeometry.point(center: CGPoint(x: 10, y: 10), radius: 5, fraction: 0)
        #expect(abs(top.x - 10) < 0.001 && abs(top.y - 5) < 0.001)
        let right = RingGeometry.point(center: CGPoint(x: 10, y: 10), radius: 5, fraction: 0.25)
        #expect(abs(right.x - 15) < 0.001 && abs(right.y - 10) < 0.001)
    }

    @Test("Dial rings: session, weekly all models, most-used model week, never twice")
    @MainActor
    func specs() throws {
        let reading = try UIFixture.reading([try UIFixture.bucket("claude", [
            try UIFixture.window("session", .session, used: 7),
            try UIFixture.window("week", .weekly(model: nil), used: 38, duration: .oneWeek),
            try UIFixture.window("week.sonnet", .weekly(model: "Sonnet"), used: 20, duration: .oneWeek),
            try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 63, duration: .oneWeek),
        ])])
        let status = AccountStatus(profile: try UIFixture.profile("Claude"), reading: reading)
        let presentation = AccountPresentation(status: status, appearance: AppearanceSettings(), now: UIFixture.now, l10n: .testRussian)
        let ids = { (limit: Int, diameter: CGFloat) in
            RingGeometry.specs(headline: presentation.headline, windows: presentation.windows, maximumRings: limit, diameter: diameter).map(\.id)
        }
        #expect(ids(3, 58) == ["claude/session", "claude/week", "claude/week.fable"])
        #expect(ids(1, 58) == ["claude/session"])
        #expect(ids(3, 36) == ["claude/session", "claude/week"])
        #expect(ids(3, 28) == ["claude/session"])

        // Without an all-models week the secondary ring is the model week; it is not repeated.
        let modelOnly = try UIFixture.reading([try UIFixture.bucket("claude", [
            try UIFixture.window("session", .session, used: 7),
            try UIFixture.window("week.fable", .weekly(model: "Fable"), used: 63, duration: .oneWeek),
        ])])
        let other = AccountPresentation(status: AccountStatus(profile: try UIFixture.profile("B"), reading: modelOnly), appearance: AppearanceSettings(), now: UIFixture.now, l10n: .testRussian)
        #expect(RingGeometry.specs(headline: other.headline, windows: other.windows, maximumRings: 3, diameter: 58).map(\.id) == ["claude/session", "claude/week.fable"])
        #expect(RingGeometry.specs(headline: nil, windows: [], maximumRings: 3, diameter: 58).isEmpty)
    }

    @Test("Orbit stays inside its margin")
    func orbit() {
        for (diameter, margin) in [(28.0, 4.0), (58.0, 4.0), (14.0, 3.0), (116.0, 8.0)] {
            let radius = OrbitGeometry.radius(diameter: diameter, margin: margin)
            let width = OrbitGeometry.lineWidth(margin: margin)
            #expect(radius - width / 2 >= diameter / 2 - 0.001)
            #expect(radius + width / 2 * 1.15 <= diameter / 2 + margin + 0.001)
        }
        let tail = OrbitGeometry.tailSegments(count: 14)
        #expect(tail.count == 14)
        #expect(abs(tail[0].from - OrbitGeometry.tailLength) < 0.0001)
        #expect(abs(tail[13].to) < 0.0001)
        for (earlier, later) in zip(tail, tail.dropFirst()) {
            #expect(abs(earlier.to - later.from) < 0.0001)
            #expect(later.opacity > earlier.opacity)
            #expect(later.width > earlier.width)
        }
        #expect(OrbitGeometry.tailSegments(count: 0).isEmpty)
    }
}
