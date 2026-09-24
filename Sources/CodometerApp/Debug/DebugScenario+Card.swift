#if DEBUG
import CodometerCore
import CodometerUI
import AppKit
import Foundation

/// Floating card steps.
///
/// `{"style": "floatingCard"}` switches the presentation style in memory, `{"cardExpand": true}` /
/// `{"cardMinimize": true}` morph the card, `{"cardDrag": {"to": [x, y], "duration": 0.6, "command": false}}` carries
/// it to a point given as fractions of the main screen (origin bottom-left) and drops it, `{"cardAccount": "next"}`
/// switches accounts, `{"cardTheme": "liquidGlass"}` and `{"cardSize": "compact"}` change its look,
/// `{"displayChange": "simulate"}` re-resolves its display and placement the way a screen-parameter change does,
/// `{"cardMouseDrag": {"to": [x, y], "steps": 24, "from": [fx, fy]}}` drags the desktop card with mouse events sent
/// through its panel, and `{"cardHitMap": true}` logs which view a click on each point of a grid over the card reaches.
extension DebugScenario {
    static func handleCardStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        func fail(_ reason: String) -> DebugScenarioError {
            DebugScenarioError(description: "\(key): \(reason)")
        }
        guard let card = context.controller.presentation.card else {
            guard Self.cardKeys.contains(key) else { return false }
            throw fail("the floating card is not installed")
        }
        switch key {
        case "style":
            guard let raw = DebugValue.string(value), let style = PresentationStyle(rawValue: raw) else {
                throw fail("expected one of \(PresentationStyle.allCases.map(\.rawValue))")
            }
            var appearance = context.island.debugSettings.appearance
            appearance.presentationStyle = style
            context.island.debugApply(appearance: appearance, general: context.island.debugSettings.general)
            card.debugApply(appearance: appearance)
            context.log(["action": "style", "style": style.rawValue])
            return true
        case "cardExpand", "cardMinimize":
            guard DebugValue.bool(value) == true else { throw fail("expected true") }
            if key == "cardExpand" {
                card.debugExpand()
            } else {
                card.debugMinimize()
            }
            return true
        case "cardAccount":
            guard let raw = DebugValue.string(value), raw == "next" || raw == "previous" else {
                throw fail("expected \"next\" or \"previous\"")
            }
            card.debugSelectAccount(raw == "next" ? 1 : -1)
            return true
        case "cardTheme":
            guard let raw = DebugValue.string(value), let theme = CardTheme(rawValue: raw) else {
                throw fail("expected one of \(CardTheme.allCases.map(\.rawValue))")
            }
            card.debugSetTheme(theme)
            return true
        case "cardSize":
            guard let raw = DebugValue.string(value), let size = CardSize(rawValue: raw) else {
                throw fail("expected one of \(CardSize.allCases.map(\.rawValue))")
            }
            card.debugSetSize(size)
            return true
        case "displayChange":
            guard DebugValue.string(value) == "simulate" else { throw fail("expected \"simulate\"") }
            card.debugSimulateDisplayChange()
            return true
        case "cardMouseDrag":
            guard let drag = DebugValue.object(value), Set(drag.keys).isSubset(of: ["to", "steps", "from"]),
                  let to = drag["to"].flatMap(DebugValue.point) else {
                throw fail("expected {to: [x, y], steps, from: [fx, fy]}")
            }
            let steps = Int(drag["steps"].flatMap(DebugValue.number) ?? 24)
            let grip = drag["from"].flatMap(DebugValue.point)
            guard (0...1).contains(to.x), (0...1).contains(to.y) else { throw fail("to must be fractions in 0…1") }
            guard let screen = NSScreen.screens.first?.frame else { return true }
            let target = CGPoint(x: screen.minX + screen.width * to.x, y: screen.minY + screen.height * to.y)
            context.background {
                await card.debugMouseDrag(to: target, steps: steps, from: grip)
            }
            return true
        case "cardHitMap":
            let map = card.debugHitMap(columns: 12, rows: 8)
            context.log(["action": "cardHitMap", "points": map])
            return true
        case "cardDrag":
            guard let drag = DebugValue.object(value), Set(drag.keys).isSubset(of: ["to", "duration", "command"]),
                  let to = drag["to"].flatMap(DebugValue.point) else {
                throw fail("expected {to: [x, y], duration, command}")
            }
            let duration = drag["duration"].flatMap(DebugValue.number) ?? 0.6
            let command = drag["command"].flatMap(DebugValue.bool) ?? false
            guard (0...1).contains(to.x), (0...1).contains(to.y) else { throw fail("to must be fractions in 0…1") }
            guard (0.05...5).contains(duration) else { throw fail("duration must be in 0.05…5 s") }
            guard let screen = NSScreen.screens.first?.frame else { return true }
            let target = CGPoint(x: screen.minX + screen.width * to.x, y: screen.minY + screen.height * to.y)
            context.background {
                await card.debugDrag(to: target, duration: duration, command: command)
            }
            return true
        default:
            return false
        }
    }

    private static let cardKeys: Set<String> = [
        "style", "cardExpand", "cardMinimize", "cardAccount", "cardTheme", "cardSize", "displayChange", "cardMouseDrag", "cardHitMap", "cardDrag",
    ]

    /// Fields this domain adds to `capture` and `trace` lines.
    static func cardTraceFields(_ context: DebugContext) -> [String: Any] {
        guard let card = context.controller.presentation.card, card.isOnScreen else { return [:] }
        let geometry = card.debugGeometry
        return [
            "form": geometry.form,
            "anchor": geometry.anchor,
            "cardFrame": json(geometry.cardFrame),
            "pillFrame": json(geometry.pillFrame),
            "cardPanel": json(geometry.panelFrame),
            "cardTheme": geometry.theme,
            "cardSize": geometry.size,
            "cardDragging": geometry.isDragging,
            "snapLocked": geometry.snapLocked,
            "displayID": geometry.displayID ?? NSNull(),
        ]
    }

    private static func json(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}
#endif
