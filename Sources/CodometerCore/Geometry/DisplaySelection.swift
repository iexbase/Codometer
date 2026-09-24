import CoreGraphics

/// One connected display, described without AppKit so selection rules stay pure and testable.
public struct DisplayDescriptor: Hashable, Sendable, Identifiable {
    public static let maximumNameLength = 64

    public let id: DisplayID
    /// The display's localized name, sanitised; empty when the system gives none (the UI shows its own fallback, and an
    /// empty name never re-adopts a display).
    public let name: String
    /// Screen coordinates, origin bottom-left of the main display.
    public let frame: CGRect
    /// The frame minus menu bar and Dock.
    public let visibleFrame: CGRect
    /// Has the menu bar (`NSScreen.screens.first`).
    public let isMain: Bool
    public let isBuiltIn: Bool
    public let notch: NotchGeometry?

    public init(
        id: DisplayID,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isMain: Bool,
        isBuiltIn: Bool,
        notch: NotchGeometry?
    ) {
        self.id = id
        self.name = DisplayText.sanitize(name, maximumLength: Self.maximumNameLength) ?? ""
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.notch = notch
    }

    /// This display as a surface remembers it.
    public var remembered: RememberedDisplay { RememberedDisplay(id: id, name: name) }
}

/// Picks displays for the island and the floating card (one rule set for both surfaces).
public enum DisplaySelection {
    /// The display a surface belongs on, or `nil` when no display is connected.
    ///
    /// - `whereLeft`: the remembered display while connected (re-adopted by a unique name when its UUID changed),
    ///   otherwise the main display.
    /// - `main`: the main display.
    /// - `display(id)`: that display while connected (re-adopted by name when `remembered` has the same id),
    ///   otherwise the main display.
    public static func resolve(policy: DisplayPolicy, remembered: RememberedDisplay?, displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        switch policy {
        case .whereLeft:
            if let remembered, let display = adopt(remembered, displays: displays) {
                return display
            }
        case .main:
            break
        case .display(let id):
            if let display = displays.first(where: { $0.id == id }) {
                return display
            }
            if let remembered, remembered.id == id, let display = adopt(remembered, displays: displays) {
                return display
            }
        }
        return main(in: displays)
    }

    /// The display containing `point`, else the nearest one by distance to its frame (a point in a gap between
    /// displays); `nil` without displays.
    public static func display(at point: CGPoint, in displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        guard point.x.isFinite, point.y.isFinite else { return main(in: displays) }
        if let inside = displays.first(where: { $0.frame.contains(point) }) {
            return inside
        }
        var best: (display: DisplayDescriptor, distance: CGFloat)?
        for display in displays {
            let distance = distance(from: point, to: display.frame)
            if best == nil || distance < (best?.distance ?? .infinity) {
                best = (display, distance)
            }
        }
        return best?.display
    }

    /// Whether a drag may land on `target`: any connected display for `whereLeft`; only the display the policy
    /// resolves to for `main` and `display(id)`.
    public static func allowsDrop(on target: DisplayDescriptor, policy: DisplayPolicy, displays: [DisplayDescriptor]) -> Bool {
        guard displays.contains(where: { $0.id == target.id }) else { return false }
        switch policy {
        case .whereLeft:
            return true
        case .main, .display:
            return resolve(policy: policy, remembered: nil, displays: displays)?.id == target.id
        }
    }

    /// The remembered display itself while connected; otherwise the only connected display with the same name.
    public static func adopt(_ remembered: RememberedDisplay, displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        if let exact = displays.first(where: { $0.id == remembered.id }) {
            return exact
        }
        guard let name = remembered.name else { return nil }
        let matches = displays.filter { !$0.name.isEmpty && $0.name == name }
        return matches.count == 1 ? matches.first : nil
    }

    /// The bounding box of every display frame; `.zero` without displays.
    public static func union(of displays: [DisplayDescriptor]) -> CGRect {
        guard let first = displays.first else { return .zero }
        return displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// The display flagged main, else the first one.
    public static func main(in displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        displays.first(where: \.isMain) ?? displays.first
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
