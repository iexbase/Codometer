#if DEBUG
import CodometerCore
import CodometerUI
import AppKit
import Foundation

/// Island steps: open, close, hover, press, click, drag, the camera notch, displays and the shortcut status.
extension DebugScenario {
    /// `{"expand": true}`, `{"collapse": true}`, `{"hover": true|false}`, `{"press": true}`, `{"click": true}`,
    /// `{"outsideClick": true}`, `{"escapeHotKey": true}`,
    /// `{"drag": {"to": [x, y], "duration": 0.8, "command": false}}` (fractions of the main screen, origin
    /// bottom-left; in the background), `{"notch": {"width": 185, "height": 32}}` or `{"notch": null}`,
    /// `{"display": "next"}`, `{"shortcutStatus": "active"|"usedByMacOS"|"usedByAnotherApp"}`.
    static func handleIslandStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        let island = context.island
        func fail(_ reason: String) -> DebugScenarioError {
            DebugScenarioError(description: "\(key): \(reason)")
        }
        switch key {
        case "expand", "collapse", "click", "outsideClick", "press", "escapeHotKey":
            guard DebugValue.bool(value) == true else { throw fail("expected true") }
            switch key {
            case "expand": island.debugExpand()
            case "collapse": island.debugCollapse()
            case "click": island.debugClick()
            case "press": island.debugPress()
            case "escapeHotKey": island.debugPressEscapeHotKey()
            default: island.debugOutsideClick()
            }
            return true
        case "hover":
            guard let inside = DebugValue.bool(value) else { throw fail("expected true or false") }
            island.debugHover(inside)
            return true
        case "islandMouseDrag":
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
                await island.debugMouseDrag(to: target, steps: steps, from: grip)
            }
            return true
        case "drag":
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
                await island.debugDrag(to: target, duration: duration, command: command)
            }
            return true
        case "notch":
            island.debugSetNotch(try notch(value, fail: fail))
            return true
        case "display":
            guard DebugValue.string(value) == "next" else { throw fail("expected \"next\"") }
            island.debugMoveToNextDisplay()
            return true
        case "shortcutStatus":
            guard let name = DebugValue.string(value) else { throw fail("expected a status name") }
            try applyShortcutStatus(name, context: context, fail: fail)
            return true
        default:
            return false
        }
    }

    /// A simulated camera notch on the island's display; `null` returns to the real geometry.
    private static func notch(_ value: Any, fail: (String) -> DebugScenarioError) throws -> NotchGeometry? {
        if value is NSNull { return nil }
        guard let object = DebugValue.object(value), Set(object.keys).isSubset(of: ["width", "height"]),
              let width = object["width"].flatMap(DebugValue.number),
              let height = object["height"].flatMap(DebugValue.number)
        else {
            throw fail("expected {width, height} or null")
        }
        guard let frame = NSScreen.screens.first?.frame else { throw fail("no screen") }
        guard width >= NotchGeometry.minimumWidth, width <= frame.width * NotchGeometry.maximumWidthFraction else {
            throw fail("width must be 60…\(Int(frame.width * NotchGeometry.maximumWidthFraction)) pt")
        }
        guard height > 0, height < frame.height else { throw fail("height must be inside the screen") }
        let aux = (frame.width - width) / 2
        guard let geometry = NotchGeometry.make(
            screen: frame,
            safeTop: height,
            auxLeft: CGRect(x: frame.minX, y: frame.maxY - height, width: aux, height: height),
            auxRight: CGRect(x: frame.minX + aux + width, y: frame.maxY - height, width: aux, height: height)
        ) else {
            throw fail("those measurements are not a usable notch")
        }
        return geometry
    }

    /// Pins the shortcut status in memory, so the conflict row can be captured without taking a real shortcut.
    private static func applyShortcutStatus(
        _ name: String,
        context: DebugContext,
        fail: (String) -> DebugScenarioError
    ) throws {
        let shortcut = context.store.settings.general.globalShortcut
        let chosen = shortcut == .off ? GlobalShortcut.controlOptionCommandU : shortcut
        let alternatives = GlobalShortcut.allCases.filter { $0 != .off && $0 != chosen }
        let status: ShortcutStatus = switch name {
        case "active": .active(chosen)
        case "usedByMacOS": .unavailable(chosen, reason: .usedByMacOS, alternatives: alternatives)
        case "usedByAnotherApp": .unavailable(chosen, reason: .usedByAnotherApp, alternatives: alternatives)
        default: throw fail("expected active, usedByMacOS or usedByAnotherApp")
        }
        context.controller.shortcuts.statusOverride = status
        context.store.setShortcutStatus(status)
    }

    /// Island fields for `capture` and `trace` lines (the island's geometry is always recorded by the runner).
    static func islandTraceFields(_ context: DebugContext) -> [String: Any] {
        let geometry = context.island.debugGeometry
        var fields: [String: Any] = [
            "notchFused": geometry.notchFused,
            "hapticCount": geometry.hapticCount,
            "snapLocked": geometry.snapTarget != nil,
            "flightCount": geometry.flightCount,
            "railAnchors": geometry.railAnchors,
            "deckAnchors": geometry.deckAnchors,
            "deckViewport": geometry.hasDeckViewport,
        ]
        if let progress = geometry.flightProgress {
            fields["flightProgress"] = progress
        }
        if let target = geometry.snapTarget {
            fields["snapTarget"] = target
        }
        if let display = geometry.displayID {
            fields["displayID"] = display
        }
        return fields
    }
}
#endif
