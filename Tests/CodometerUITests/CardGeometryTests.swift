import CodometerCore
@testable import CodometerUI
import CoreGraphics
import Foundation
import Testing

/// Where the floating card sits: the magnet, gravity, placements, clamping and the display rules.
@Suite("Card geometry")
struct CardGeometryTests {
    /// A 1440 × 900 display with a 25 pt menu bar and a 70 pt Dock.
    static func display(
        id: String = "11111111-1111-4111-8111-111111111111",
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 1_440, height: 900),
        name: String = "Built-in",
        isMain: Bool = true,
        notch: NotchGeometry? = nil
    ) throws -> DisplayDescriptor {
        let frame = CGRect(origin: origin, size: size)
        return DisplayDescriptor(
            id: try DisplayID(id),
            name: name,
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY + 70, width: frame.width, height: frame.height - 70 - 25),
            isMain: isMain,
            isBuiltIn: true,
            notch: notch
        )
    }

    static let cardSize = CGSize(width: 344, height: 268)
    static let radius = MagnetLaw.radius

    // MARK: - Stage

    @Test("The stage keeps the card inside the visible frame, away from the menu bar and the Dock")
    func stageRespectsChrome() throws {
        let display = try Self.display()
        let stage = FloatingCardGeometry.stage(of: display)
        #expect(stage.minY == display.visibleFrame.minY + CardMetrics.screenInset)
        #expect(stage.maxY == display.visibleFrame.maxY - CardMetrics.screenInset)
        #expect(stage.minX == display.frame.minX + CardMetrics.screenInset)
        #expect(stage.width == display.frame.width - CardMetrics.screenInset * 2)
    }

    @Test("A notch pushes the stage further down than the menu bar alone")
    func stageRespectsNotch() throws {
        let frame = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let notch = try #require(NotchGeometry.make(
            screen: frame,
            safeTop: 38,
            auxLeft: CGRect(x: 0, y: frame.maxY - 38, width: 660, height: 38),
            auxRight: CGRect(x: 852, y: frame.maxY - 38, width: 660, height: 38)
        ))
        let plain = try Self.display(size: frame.size)
        let notched = try Self.display(size: frame.size, notch: notch)
        #expect(FloatingCardGeometry.stage(of: notched).maxY < FloatingCardGeometry.stage(of: plain).maxY)
        #expect(FloatingCardGeometry.stage(of: notched).maxY <= notch.rect.minY)
    }

    // MARK: - Anchors and gravity

    @Test("Card and pill share their anchor point, so minimize and restore never drift")
    func anchorsShared() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        for anchor in CardAnchor.allCases {
            let point = FloatingCardGeometry.targetPoint(anchor, in: stage)
            let card = FloatingCardGeometry.frame(size: Self.cardSize, anchor: anchor, at: point)
            let pill = FloatingCardGeometry.frame(size: CGSize(width: 152, height: 40), anchor: anchor, at: point)
            #expect(FloatingCardGeometry.anchorPoint(of: card, anchor: anchor) == point)
            #expect(FloatingCardGeometry.anchorPoint(of: pill, anchor: anchor) == point)
        }
    }

    @Test("A hundred minimize and restore round trips land on exactly the same pixels, at every scale")
    func zeroDriftOverRoundTrips() throws {
        let display = try Self.display()
        let stage = FloatingCardGeometry.stage(of: display)
        for scale in [0.75, 1.0, 1.5] {
            let metrics = CardMetrics(scale: scale)
            let card = metrics.cardSize(.regular)
            let pill = metrics.pillSize(
                accounts: 1,
                templates: CardPillTemplates(percent: "88%", countdown: "88d 88h", more: "+8")
            )
            for anchor in CardAnchor.allCases {
                let placement = CardPlacement(displayID: display.id, anchor: anchor, snapped: true, x: .zero, y: .zero)
                let first = FloatingCardGeometry.frame(for: placement, size: card, in: stage)
                var current = first
                for _ in 0..<100 {
                    let point = FloatingCardGeometry.anchorPoint(of: current, anchor: anchor)
                    let minimized = FloatingCardGeometry.frame(size: pill, anchor: anchor, at: point)
                    let back = FloatingCardGeometry.frame(
                        size: card,
                        anchor: anchor,
                        at: FloatingCardGeometry.anchorPoint(of: minimized, anchor: anchor)
                    )
                    current = back
                }
                #expect(current == first, "drift at scale \(scale), anchor \(anchor)")
            }
        }
    }

    @Test("Gravity follows the ninth of the stage the card's centre is in")
    func gravityByNinths() throws {
        let stage = CGRect(x: 0, y: 0, width: 900, height: 900)
        let expectations: [(CGPoint, CardAnchor)] = [
            (CGPoint(x: 100, y: 800), .topLeading),
            (CGPoint(x: 450, y: 800), .top),
            (CGPoint(x: 800, y: 800), .topTrailing),
            (CGPoint(x: 100, y: 450), .leading),
            (CGPoint(x: 450, y: 450), .center),
            (CGPoint(x: 800, y: 450), .trailing),
            (CGPoint(x: 100, y: 100), .bottomLeading),
            (CGPoint(x: 450, y: 100), .bottom),
            (CGPoint(x: 800, y: 100), .bottomTrailing),
        ]
        for (center, anchor) in expectations {
            let frame = CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)
            #expect(FloatingCardGeometry.gravity(of: frame, in: stage) == anchor, "centre \(center)")
        }
    }

    // MARK: - The magnet

    @Test("Inside half the radius the card sits exactly on the target")
    func lockedCoreIsExact() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        let target = FloatingCardGeometry.targetPoint(.topTrailing, in: stage)
        let exact = FloatingCardGeometry.frame(size: Self.cardSize, anchor: .topTrailing, at: target)
        for offset in [CGPoint(x: 3, y: -4), CGPoint(x: -10, y: 8), CGPoint(x: 0, y: 0)] {
            let free = exact.offsetBy(dx: offset.x, dy: offset.y)
            let resolution = FloatingCardGeometry.resolve(free: free, in: stage, radius: Self.radius, snaps: true)
            #expect(resolution.frame == exact)
            #expect(resolution.snappedAnchor == .topTrailing)
            #expect(resolution.isLocked)
        }
    }

    @Test("The magnet never jumps: a hundredth of a point of travel moves the card by less than half a point")
    func magnetIsContinuous() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        let sample: CGFloat = 0.01
        var previous: CGRect?
        var worstGain: CGFloat = 0
        // A diagonal sweep across the whole stage passes every corner, every edge midpoint and the centre.
        for step in 0...120_000 {
            let progress = CGFloat(step) * sample
            let free = CGRect(
                x: stage.minX + progress,
                y: stage.minY + progress * (stage.height / 1_200),
                width: Self.cardSize.width,
                height: Self.cardSize.height
            )
            let resolved = FloatingCardGeometry.resolve(free: free, in: stage, radius: Self.radius, snaps: true).frame
            if let previous {
                let jump = hypot(resolved.minX - previous.minX, resolved.minY - previous.minY)
                #expect(jump < 0.5, "jump \(jump) at \(progress) pt")
                worstGain = max(worstGain, jump / hypot(sample, sample * stage.height / 1_200))
            }
            previous = resolved
        }
        // The pull eases in over half the radius, so the card can move a few times faster than the pointer inside the
        // soft zone — but never further than the radius itself, and never in a step.
        #expect(worstGain < 4, "the magnet amplifies pointer motion \(worstGain)×")
    }

    @Test("Near an edge but far from a target only that axis locks, so the card slides along the edge")
    func edgeLineLocksOneAxis() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        // Vertically on the top edge, horizontally a third of the way across: far from every x target.
        let free = CGRect(
            x: stage.minX + stage.width * 0.28,
            y: stage.maxY - Self.cardSize.height - 4,
            width: Self.cardSize.width,
            height: Self.cardSize.height
        )
        let resolution = FloatingCardGeometry.resolve(free: free, in: stage, radius: Self.radius, snaps: true)
        #expect(resolution.frame.maxY == stage.maxY)
        #expect(resolution.frame.minX == free.minX)
        #expect(resolution.snappedAnchor == nil)
        #expect(resolution.targetID == "y:end")
    }

    @Test("⌘ turns the magnet off for that drag")
    func commandBypassesTheMagnet() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        let target = FloatingCardGeometry.targetPoint(.topTrailing, in: stage)
        let free = FloatingCardGeometry.frame(size: Self.cardSize, anchor: .topTrailing, at: target).offsetBy(dx: -5, dy: 3)
        let resolution = FloatingCardGeometry.resolve(free: free, in: stage, radius: Self.radius, snaps: false)
        #expect(resolution.frame == free)
        #expect(resolution.snappedAnchor == nil)
        #expect(resolution.targetID == nil)
    }

    @Test("Beyond the radius the card follows the pointer exactly")
    func freeBeyondTheRadius() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        // A third of the way across and a third of the way up: far from every corner, edge and the centre.
        let free = CGRect(
            x: stage.minX + stage.width * 0.3,
            y: stage.minY + stage.height * 0.2,
            width: Self.cardSize.width,
            height: Self.cardSize.height
        )
        let resolution = FloatingCardGeometry.resolve(free: free, in: stage, radius: Self.radius, snaps: true)
        #expect(resolution.frame == free)
        #expect(resolution.targetID == nil)
        #expect(resolution.distance > Self.radius)
    }

    @Test("The haptic arms once per lock and re-arms only after the pointer leaves the radius")
    func hapticArming() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        let target = FloatingCardGeometry.targetPoint(.bottomLeading, in: stage)
        let exact = FloatingCardGeometry.frame(size: Self.cardSize, anchor: .bottomLeading, at: target)
        var arming = MagnetArming()
        var now = 100.0
        func feed(_ frame: CGRect) -> Bool {
            let resolution = FloatingCardGeometry.resolve(free: frame, in: stage, radius: Self.radius, snaps: true)
            now += 0.5
            return arming.update(targetID: resolution.targetID, distance: resolution.distance, radius: Self.radius, now: now)
        }
        #expect(feed(exact))
        #expect(!feed(exact))
        // Still inside the radius: no second tap.
        #expect(!feed(exact.offsetBy(dx: 20, dy: 20)))
        // Away and back: one more tap.
        #expect(!feed(exact.offsetBy(dx: 300, dy: 300)))
        #expect(feed(exact))
    }

    // MARK: - Clamping and fitting

    @Test("Clamping keeps the whole card inside the stage")
    func clampKeepsTheCardOnScreen() throws {
        let stage = FloatingCardGeometry.stage(of: try Self.display())
        let outside = CGRect(x: stage.maxX - 20, y: stage.minY - 200, width: Self.cardSize.width, height: Self.cardSize.height)
        let clamped = FloatingCardGeometry.clamp(outside, in: stage)
        #expect(stage.contains(clamped))
        #expect(clamped.maxX == stage.maxX)
        #expect(clamped.minY == stage.minY)
    }

    @Test("A card that does not fit falls back to the next smaller size, and to nothing when even that fails")
    func fitFallback() {
        let metrics = CardMetrics(scale: 1.5)
        let roomy = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        #expect(metrics.fittingSize(.regular, in: roomy) == .regular)
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 400)
        #expect(metrics.fittingSize(.regular, in: narrow) == .compact)
        let tiny = CGRect(x: 0, y: 0, width: 120, height: 120)
        #expect(metrics.fittingSize(.regular, in: tiny) == nil)
    }

    @Test("The strip fits a wide stage, falls back to Regular on a narrow one, and never grows past what was asked")
    func stripFallsBackToRegular() {
        let metrics = CardMetrics(scale: 1)
        let roomy = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        #expect(metrics.fittingSize(.strip, in: roomy) == .strip)
        // Wide enough for Regular but not for the strip.
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 400)
        #expect(metrics.fittingSize(.strip, in: narrow) == .regular)
        // Too short for Regular, wide enough for the strip: the strip itself fits.
        let short = CGRect(x: 0, y: 0, width: 700, height: 220)
        #expect(metrics.fittingSize(.strip, in: short) == .strip)
        #expect(metrics.fittingSize(.regular, in: short) == .compact)
        // A smaller choice never escalates to the strip.
        #expect(metrics.fittingSize(.regular, in: roomy) == .regular)
        #expect(metrics.fittingSize(.compact, in: roomy) == .compact)
        let stripSize = metrics.cardSize(.strip)
        #expect(stripSize.width > metrics.cardSize(.regular).width)
        #expect(stripSize.height < metrics.cardSize(.regular).height)
    }

    // MARK: - Placements

    @Test("A snapped placement lands exactly on its target however the display changed")
    func snappedPlacementSurvivesResolutionChanges() throws {
        let small = try Self.display(size: CGSize(width: 1_280, height: 800))
        let large = try Self.display(size: CGSize(width: 2_560, height: 1_440))
        let placement = CardPlacement(displayID: small.id, anchor: .bottomTrailing, snapped: true, x: .one, y: .one)
        for display in [small, large] {
            let stage = FloatingCardGeometry.stage(of: display)
            let frame = FloatingCardGeometry.frame(for: placement, size: Self.cardSize, in: stage)
            #expect(frame.maxX == stage.maxX)
            #expect(frame.minY == stage.minY)
        }
    }

    @Test("A free placement keeps its anchor point at the same fractions of the stage")
    func freePlacementRescales() throws {
        let display = try Self.display()
        let stage = FloatingCardGeometry.stage(of: display)
        let frame = CGRect(x: stage.minX + 300, y: stage.minY + 200, width: Self.cardSize.width, height: Self.cardSize.height)
        let placement = FloatingCardGeometry.placement(of: frame, on: display, stage: stage, snappedAnchor: nil)
        #expect(!placement.snapped)
        let back = FloatingCardGeometry.frame(for: placement, size: Self.cardSize, in: stage)
        #expect(abs(back.minX - frame.minX) < 0.001)
        #expect(abs(back.minY - frame.minY) < 0.001)

        let wider = try Self.display(size: CGSize(width: 2_880, height: 1_800))
        let widerStage = FloatingCardGeometry.stage(of: wider)
        let rescaled = FloatingCardGeometry.frame(for: placement, size: Self.cardSize, in: widerStage)
        let anchor = FloatingCardGeometry.anchorPoint(of: rescaled, anchor: placement.anchor)
        #expect(abs((anchor.x - widerStage.minX) / widerStage.width - placement.x.value) < 0.001)
    }

    @Test("Placements are remembered per display, most recent first, at most eight")
    func placementsPerDisplay() throws {
        var placements = FloatingCardPlacements.empty
        for index in 0..<12 {
            let id = try DisplayID(String(format: "22222222-2222-4222-8222-%012d", index))
            placements.remember(CardPlacement(displayID: id, anchor: .top, snapped: true, x: .half, y: .zero))
        }
        #expect(placements.byDisplay.count == FloatingCardPlacements.maximumCount)
        let newest = try DisplayID(String(format: "22222222-2222-4222-8222-%012d", 11))
        #expect(placements.byDisplay.first?.displayID == newest)
        // The same display again replaces its entry instead of adding one.
        placements.remember(CardPlacement(displayID: newest, anchor: .bottom, snapped: true, x: .half, y: .one))
        #expect(placements.byDisplay.count == FloatingCardPlacements.maximumCount)
        #expect(placements.placement(for: newest)?.anchor == .bottom)
    }

    // MARK: - Displays coming and going

    @Test("Unplugging the card's display moves it to the main one and remembers where it came from")
    func displayDisconnectMovesToMain() throws {
        let built = try Self.display(id: "33333333-3333-4333-8333-333333333333", name: "Built-in")
        let external = try Self.display(
            id: "44444444-4444-4444-8444-444444444444",
            origin: CGPoint(x: 1_440, y: 0),
            name: "LG UltraFine",
            isMain: false
        )
        var placements = FloatingCardPlacements.empty
        placements.remember(CardPlacement(displayID: external.id, anchor: .bottomTrailing, snapped: true, x: .one, y: .one))
        placements.remember(CardPlacement(displayID: built.id, anchor: .topLeading, snapped: true, x: .zero, y: .zero))
        placements.current = external.id

        let gone = try #require(FloatingCardGeometry.plan(policy: .whereLeft, placements: placements, displays: [built]))
        #expect(gone.display.id == built.id)
        #expect(gone.placement.anchor == .topLeading)
        #expect(gone.updatedPlacements?.displacedFrom == external.id)

        // The display is back and the user has not dragged since: the card returns to it.
        let displaced = try #require(gone.updatedPlacements)
        let back = try #require(FloatingCardGeometry.plan(
            policy: .whereLeft,
            placements: displaced,
            displays: [built, external]
        ))
        #expect(back.display.id == external.id)
        #expect(back.placement.anchor == .bottomTrailing)
        #expect(back.updatedPlacements?.displacedFrom == nil)
    }

    @Test("A card on a display that is still there stays put")
    func displayStaysPut() throws {
        let built = try Self.display(id: "55555555-5555-4555-8555-555555555555")
        let external = try Self.display(
            id: "66666666-6666-4666-8666-666666666666",
            origin: CGPoint(x: 1_440, y: 0),
            isMain: false
        )
        var placements = FloatingCardPlacements.empty
        placements.remember(CardPlacement(displayID: external.id, anchor: .center, snapped: true, x: .half, y: .half))
        placements.current = external.id
        let plan = try #require(FloatingCardGeometry.plan(policy: .whereLeft, placements: placements, displays: [built, external]))
        #expect(plan.display.id == external.id)
        #expect(plan.placement.anchor == .center)
    }

    @Test("“Main display” and a named display win over where the card was left")
    func policyWinsOverMemory() throws {
        let built = try Self.display(id: "77777777-7777-4777-8777-777777777777")
        let external = try Self.display(
            id: "88888888-8888-4888-8888-888888888888",
            origin: CGPoint(x: 1_440, y: 0),
            isMain: false
        )
        var placements = FloatingCardPlacements.empty
        placements.current = external.id
        let main = try #require(FloatingCardGeometry.plan(policy: .main, placements: placements, displays: [built, external]))
        #expect(main.display.id == built.id)
        let named = try #require(FloatingCardGeometry.plan(
            policy: .display(external.id),
            placements: placements,
            displays: [built, external]
        ))
        #expect(named.display.id == external.id)
    }

    @Test("A card with no placement yet starts snapped into the top-right corner")
    func defaultPlacement() throws {
        let display = try Self.display()
        let plan = try #require(FloatingCardGeometry.plan(policy: .whereLeft, placements: .empty, displays: [display]))
        #expect(plan.placement.anchor == .topTrailing)
        #expect(plan.placement.snapped)
        let stage = FloatingCardGeometry.stage(of: display)
        let frame = FloatingCardGeometry.frame(for: plan.placement, size: Self.cardSize, in: stage)
        #expect(frame.maxX == stage.maxX)
        #expect(frame.maxY == stage.maxY)
    }

    @Test("With no display connected there is nothing to plan")
    func noDisplays() {
        #expect(FloatingCardGeometry.plan(policy: .whereLeft, placements: .empty, displays: []) == nil)
    }

    // MARK: - Picking a display while dragging

    @Test("The target display is the one under the pointer, and the nearest one when the pointer is in a gap")
    func displayUnderPointer() throws {
        let left = try Self.display(id: "99999999-9999-4999-8999-999999999999")
        let right = try Self.display(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            origin: CGPoint(x: 1_600, y: 0),
            isMain: false
        )
        let displays = [left, right]
        #expect(DisplaySelection.display(at: CGPoint(x: 200, y: 200), in: displays)?.id == left.id)
        #expect(DisplaySelection.display(at: CGPoint(x: 1_700, y: 200), in: displays)?.id == right.id)
        // In the 160 pt gap between them, closer to the right one.
        #expect(DisplaySelection.display(at: CGPoint(x: 1_560, y: 200), in: displays)?.id == right.id)
        // A named-display policy refuses drops elsewhere.
        #expect(!DisplaySelection.allowsDrop(on: right, policy: .display(left.id), displays: displays))
        #expect(DisplaySelection.allowsDrop(on: right, policy: .whereLeft, displays: displays))
    }
}
