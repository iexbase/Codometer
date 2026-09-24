import CodometerCore
import CodometerL10n
import AppKit
import CoreGraphics
import SwiftUI

/// Every size of the floating card, derived from one scale factor, exactly like `IslandMetrics` for the island.
///
/// The expanded card has a fixed size per `CardSize`, so no value it shows can ever resize it: text only has to fit.
/// The minimized pill has no fixed size in points, because its width follows the measured widths of the hidden
/// templates (`CardStrings.percentTemplate` and friends), which is what keeps it the same width in both languages
/// whatever the numbers say.
public struct CardMetrics: Equatable, Sendable {
    /// Compact card at scale 1.
    public static let compactSize = CGSize(width: 208, height: 208)
    /// Regular card at scale 1 (the default).
    public static let regularSize = CGSize(width: 344, height: 268)
    /// Strip card at scale 1: wide and short, the binding week on the left and a row of chips on the right.
    public static let stripSize = CGSize(width: 560, height: 136)
    /// How many chips the strip has room for; windows beyond that collapse into one "+N" chip.
    public static let stripChipCapacity = 3
    /// Height of the minimized pill at scale 1.
    public static let pillHeight: CGFloat = 40
    /// How far inside a display's visible frame the card may sit, so the menu bar, the Dock and the notch safe area
    /// are respected. Not scaled: it is a property of the screen, not of the card.
    public static let screenInset: CGFloat = 12

    public let scale: CGFloat

    public init(scale: CGFloat) {
        self.scale = max(0.1, scale)
    }

    /// The scale the card's *frame* follows.
    ///
    /// Text has floors (`IslandMetrics.textSize`), so below 1.0 glyphs stay larger than the raw scale would make them.
    /// If the frame shrank faster than the glyphs, the widest template would stop fitting at 0.75×. The layout scale
    /// therefore never falls below the text's own floor ratio. It depends on the scale only, never on the language, so
    /// English and Russian always get exactly the same card.
    public var layoutScale: CGFloat {
        max(scale, IslandMetrics.textSize(TextSize.callout, scale: scale) / TextSize.callout)
    }

    public init(_ scale: IslandScale) {
        self.init(scale: scale.value)
    }

    /// Transparent room around the card inside its panel, for the shadow, the rim and the morph's wobble.
    public var windowMargin: CGFloat { 22 * layoutScale }
    /// The furthest the morphing contour may bow outside its frame: well inside `windowMargin`.
    public var wobble: CGFloat { 5 * layoutScale }

    public var cardCorner: CGFloat { 26 * layoutScale }
    public var pillHeight: CGFloat { Self.pillHeight * layoutScale }
    public var pillCorner: CGFloat { pillHeight / 2 }
    public var padding: CGFloat { 12 * layoutScale }
    public var pillPadding: CGFloat { 8 * layoutScale }
    public var tileSpacing: CGFloat { 7 * layoutScale }
    public var tileCorner: CGFloat { 13 * layoutScale }
    public var tilePadding: CGFloat { 6 * layoutScale }
    public var rowSpacing: CGFloat { 10 * layoutScale }
    /// Side of the minimize button's hit target; never below the accessibility minimum.
    public var minimizeButton: CGFloat { max(24, 24 * layoutScale) }
    public var badge: CGFloat { 20 * layoutScale }
    public var pillRing: CGFloat { 24 * layoutScale }
    /// The room one mini ring takes in the pill, including the margin its activity orbit needs.
    public var pillRingSlot: CGFloat { pillRing + max(2, pillRing / 7) * 2 }
    public var pageDot: CGFloat { 5 * layoutScale }
    /// The coach mark's fixed height and the gap between it and the card.
    public var coachMarkHeight: CGFloat { 26 * layoutScale }
    public var coachMarkGap: CGFloat { 6 * layoutScale }
    /// Room the canvas and the panel add on the coach mark's side while it is shown.
    public var coachMarkReserve: CGFloat { coachMarkHeight + coachMarkGap + 2 }

    /// Outer diameter of the hero ring, without its orbit margin. The strip draws no ring; its value only keeps the
    /// sizes exhaustive.
    public func heroRing(_ size: CardSize) -> CGFloat {
        switch size {
        case .compact: 84 * layoutScale
        case .regular: 96 * layoutScale
        case .strip: 72 * layoutScale
        }
    }

    /// The expanded card's size, which never depends on its content or its language.
    public func cardSize(_ size: CardSize) -> CGSize {
        let base = switch size {
        case .compact: Self.compactSize
        case .regular: Self.regularSize
        case .strip: Self.stripSize
        }
        return CGSize(width: (base.width * layoutScale).rounded(), height: (base.height * layoutScale).rounded())
    }

    /// The largest size that still fits `stage` with the window margin; `nil` when not even Compact fits.
    ///
    /// The strip is the widest form, so it falls back to Regular, which falls back to Compact. Never saved: a small
    /// display or a large scale falls back for this session only.
    public func fittingSize(_ size: CardSize, in stage: CGRect) -> CardSize? {
        let order: [CardSize] = [.strip, .regular, .compact]
        guard let start = order.firstIndex(of: size) else { return nil }
        for candidate in order[start...] {
            let needed = cardSize(candidate)
            if needed.width <= stage.width, needed.height <= stage.height {
                return candidate
            }
        }
        return nil
    }

    /// The width every row of the card gets: the card minus its padding. Rows take it exactly, so a long value can
    /// never make a row wider than the card.
    public func innerWidth(_ size: CardSize) -> CGFloat {
        cardSize(size).width - padding * 2
    }

    /// The width of one of the three tiles. Fixed, so a long value can never push its neighbours out of the card.
    public func tileWidth(_ size: CardSize) -> CGFloat {
        ((innerWidth(size) - tileSpacing * 2) / 3).rounded(.down)
    }

    /// The width one tile's value and label may take, inside its own padding.
    public func tileContentWidth(_ size: CardSize) -> CGFloat {
        tileWidth(size) - tilePadding * 2
    }

    /// The width the header leaves for the account chip and the status pill.
    public func headerWidth(_ size: CardSize) -> CGFloat {
        innerWidth(size) - minimizeButton * 0.9
    }

    /// The width the status pill's reserved slot takes.
    public func statusSlotWidth(template: String) -> CGFloat {
        width(of: template, role: .pill) + tilePadding * 2 + 2
    }

    // MARK: - Strip

    /// The height of the header row: the account chip's minimum, or the badge when the scale makes it taller.
    public var headerHeight: CGFloat { max(24, badge) }
    /// The strip's hero column. Fixed, so the chips never move when the numbers or the language change.
    public var stripHeroWidth: CGFloat { 220 * layoutScale }
    /// The gap between the hero column and the first chip.
    public var stripGap: CGFloat { 12 * layoutScale }
    /// The room the strip's body row (hero and chips) gets under the header.
    public var stripBodyHeight: CGFloat { cardSize(.strip).height - padding * 2 - headerHeight - rowSpacing }
    public var chipSpacing: CGFloat { 7 * layoutScale }
    public var chipPadding: CGFloat { 5 * layoutScale }
    public var chipCorner: CGFloat { 11 * layoutScale }
    /// Every chip is this tall, whatever it says.
    public var chipHeight: CGFloat { 60 * layoutScale }
    /// Every chip is this wide: the room right of the hero split into `stripChipCapacity` equal slots.
    public var chipWidth: CGFloat {
        let slots = CGFloat(Self.stripChipCapacity)
        let room = innerWidth(.strip) - stripHeroWidth - stripGap - chipSpacing * (slots - 1)
        return (room / slots).rounded(.down)
    }
    /// The width a chip's title, value and countdown may take, inside its own padding.
    public var chipContentWidth: CGFloat { chipWidth - chipPadding * 2 }

    public func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: textSize(size), weight: weight, design: .rounded)
    }

    public func digits(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: textSize(size), weight: weight, design: .rounded).monospacedDigit()
    }

    /// The same floors as the island, so small text stays legible at 0.75×.
    public func textSize(_ size: CGFloat) -> CGFloat {
        IslandMetrics.textSize(size, scale: scale)
    }

    /// The point size of every text the card draws, by role. Kept here so the fit tests measure exactly what the views
    /// render.
    public enum Role: Sendable, CaseIterable {
        case hero
        case heroUnit
        case header
        case plan
        case pill
        case tileValue
        case tileLabel
        case footer

        var designSize: CGFloat {
            switch self {
            case .hero: TextSize.hero
            case .heroUnit: TextSize.caption
            case .header: TextSize.headline
            case .plan: TextSize.badge
            case .pill: TextSize.badge
            case .tileValue: TextSize.callout
            case .tileLabel: TextSize.badge
            case .footer: TextSize.caption
            }
        }

        var weight: Font.Weight {
            switch self {
            case .hero: .semibold
            case .heroUnit, .tileLabel, .footer: .regular
            case .header: .semibold
            case .plan, .pill: .semibold
            case .tileValue: .semibold
            }
        }

        var isMonospacedDigit: Bool {
            switch self {
            case .hero, .tileValue, .pill: true
            default: false
            }
        }
    }

    public func font(_ role: Role) -> Font {
        role.isMonospacedDigit ? digits(role.designSize, role.weight) : font(role.designSize, role.weight)
    }

    /// The `NSFont` the fit tests measure `role` with: the same family, weight and size SwiftUI renders.
    public func nsFont(_ role: Role) -> NSFont {
        let size = textSize(role.designSize)
        let weight: NSFont.Weight = switch role.weight {
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
        let base = role.isMonospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    /// The width `text` takes in `role`'s font, rounded up to a whole point.
    public func width(of text: String, role: Role) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).size(withAttributes: [.font: nsFont(role)]).width.rounded(.up)
    }

    /// The minimized pill's size for `accounts` accounts, measured from the hidden templates only, so live values
    /// never change it. One account shows a ring, its percentage and its countdown; several show up to three mini
    /// rings and a "+N" badge.
    ///
    /// `templates` carries one set per language the app speaks (`CardPillTemplates.everyLanguage`), and every slot
    /// reserves the widest of them: that is what keeps the minimized card exactly the same size when the language
    /// changes, the way the expanded card's fixed size does.
    public func pillSize(accounts: Int, templates: [CardPillTemplates]) -> CGSize {
        let height = pillHeight
        let ring = pillRingSlot
        let gap = 6 * layoutScale
        let padding = pillPadding
        func widest(_ slot: (CardPillTemplates) -> String) -> CGFloat {
            templates.map { width(of: slot($0), role: .pill) }.max() ?? 0
        }
        if accounts <= 1 {
            let text = widest(\.percent) + gap + widest(\.countdown)
            return CGSize(width: (padding * 2 + ring + gap + text).rounded(.up), height: height)
        }
        let rings = min(accounts, 3)
        var content = CGFloat(rings) * ring + CGFloat(rings - 1) * (gap * 0.5)
        if accounts > rings {
            content += gap + widest(\.more)
        }
        return CGSize(width: (padding * 2 + content).rounded(.up), height: height)
    }

    /// The pill's size with one language's templates. Only the tests that measure a single language use it; the card
    /// itself always reserves every language.
    public func pillSize(accounts: Int, templates: CardPillTemplates) -> CGSize {
        pillSize(accounts: accounts, templates: [templates])
    }
}

/// The hidden template strings the pill reserves room for, in the current language.
public struct CardPillTemplates: Hashable, Sendable {
    public let percent: String
    public let countdown: String
    public let more: String

    public init(percent: String, countdown: String, more: String) {
        self.percent = percent
        self.countdown = countdown
        self.more = more
    }

    /// The templates one language writes.
    public init(_ l10n: Localizer) {
        self.init(percent: l10n.card.percentTemplate, countdown: l10n.card.countdownTemplate, more: l10n.card.moreTemplate)
    }

    /// One set per language the app speaks. The pill reserves the widest of them, so switching the language never
    /// resizes the minimized card.
    public static let everyLanguage: [CardPillTemplates] = Language.allCases.map { CardPillTemplates(Localizer(language: $0)) }
}
