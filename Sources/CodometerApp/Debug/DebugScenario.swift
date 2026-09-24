#if DEBUG
import CodometerCore
import CodometerL10n
import CodometerPlatform
import CodometerUI
import AppKit
import ApplicationServices
import Foundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import os

// README — scripted runs for visual verification. Compiled into DEBUG builds only.
//
// Run a debug build with two environment variables (and an isolated data root):
//
//     CODOMETER_DATA_ROOT=~/Library/Caches/<dev folder>/data/<task> \
//     CODOMETER_DEBUG_SCENARIO=/abs/path/scenario.json \
//     CODOMETER_DEBUG_OUT=/abs/path/out-dir \
//     build/Codometer.app/Contents/MacOS/Codometer
//
// The scenario is a JSON array of steps (or {"steps": [...]}), run one after another about a second after
// launch. Every step object has exactly one key. This file runs the generic steps; any other key goes to the domain
// handlers (`DebugScenario+Island`, `+Visuals`, `+Card`, `+Reliability`, `+Settings`, `+Onboarding`, `+Status`) when the
// step runs, and a key no handler knows is logged as an error.
//
// Generic steps:
//
//     {"settings": {...}}   in-memory overrides, never saved: any AppearanceSettings key (edge, offset, style,
//                           surface, scale, openTrigger, glowsWithUrgency, railGroupFilter, …) or GeneralSettings
//                           key (globalShortcut, …), flat or nested under "appearance" / "general"; validated by
//                           the settings' own decoders. "railGroupFilter" (a group's UUID, or null for every group)
//                           is mirrored into the store in memory, so the rail and the deck show that group
//     {"fixture": "multi"}  replaces accounts, state and analytics with synthetic data in memory ("single", "standard",
//                           "multi", "limits" or "empty"); engine updates are ignored and nothing is saved from then on.
//                           Every capture used for review, docs or screenshots uses a fixture
//     {"language": "ru"}    the interface language in memory ("en", "ru" or "system")
//     {"settingsPane": "diagnostics"}
//                           opens Settings on a pane ("accounts", "presentation", "appearance", "alerts", "general",
//                           "diagnostics"); its window is "settings" for capture, trace and axdump. View and layer draws of
//                           the Settings window come out empty, so without ScreenCaptureKit those captures and every axdump
//                           of "settings" draw the selected pane on its own in an off-screen stand-in (`"standIn": true`)
//     {"popover": true|false}
//                           opens or closes the menu bar popover; its window is "popover"
//     {"page": "timeline"}  shows a deck page in every deck ("overview" or "timeline"), like its segmented control
//     {"range": "day"}      sets the timeline range ("fiveHours", "day" or "week"), like its segmented control
//     {"reduceMotion": true|false|"system"}
//                           overrides Reduce Motion for the island's motion in memory ("system" follows the system
//                           setting again): true morphs as a plain crossfade and resize, without droplet or wobble
//     {"wait": seconds}     0…60
//     {"monitor": seconds}  in the background, logs every main-thread stall longer than 24 ms for that long
//                           ("stall" lines with the gap in ms), then one summary line; steps continue at once
//     {"capture": {"name": "top-expand", "frames": 17, "interval": 0.05, "window": "island"}}
//                           `frames` (1…120) PNGs, `interval` (0…5 s) apart, starting now. "window" is "island" (the
//                           default: one fixed screen region covering the rail and the deck), "card", "popover",
//                           "settings" or "onboarding" (the window's frame); the step ends when the last image has landed
//     {"trace": {"name": "right-fold", "frames": 60, "interval": 0.016}}
//                           like "capture", but records only the geometry line (no image), so it never stalls the
//                           main thread: the panel's exact timing through an opening or a fold; "action" is "trace"
//     {"axdump": {"name": "settings-general", "window": "settings"}}
//                           writes `ax-<name>.json`: the window's accessibility tree as VoiceOver reads it (role, subrole,
//                           label, title, value, help, identifier, frame, actions, children; depth ≤ 40, ≤ 3000 elements,
//                           ≤ 20 s). Caution: dumping a deck that shows a usage chart (the expanded island, the popover)
//                           crashed debug builds in Swift Charts' accessibility (2026-09-17); dump rails, settings panes,
//                           the card and onboarding
//     {"quit": true}        waits for pending captures, then quits
//
// Island steps (`DebugScenario+Island`): {"expand": true} opens the deck (pinned, like the shortcut), {"collapse": true}
// closes it (like Esc), {"hover": true|false} the pointer arrives on / leaves the island (the real pointer is ignored
// afterwards), {"click": true}, {"outsideClick": true} (what the outside-click monitor reports while a deck is pinned),
// {"drag": {"to": [0.98, 0.3], "duration": 0.8}} carries the island from its centre to a point given as fractions of
// the main screen (origin bottom-left) and drops it, in the background so captures can follow.
//
// The liquid morph (droplet opening and fold each settle in about 0.4 s) is best reviewed at 30 fps: "interval": 0.033
// with "frames": 24 covers an opening and its settle. Sample (hover, click and fold on three placements; repeat with
// "surface": "glass" for Liquid Glass):
//
// [
//   {"fixture": "multi"},
//   {"language": "en"},
//   {"settings": {"edge": "right", "offset": 0.5, "style": "attached", "openTrigger": "hover", "surface": "solid"}},
//   {"wait": 1},
//   {"hover": true},
//   {"capture": {"name": "right-swell-open", "frames": 24, "interval": 0.033}},
//   {"wait": 0.5},
//   {"hover": false},
//   {"wait": 0.3},
//   {"capture": {"name": "right-fold", "frames": 18, "interval": 0.033}},
//   {"settings": {"edge": "top", "offset": 0.5, "openTrigger": "click"}},
//   {"wait": 1},
//   {"click": true},
//   {"capture": {"name": "top-click-open", "frames": 24, "interval": 0.033}},
//   {"collapse": true},
//   {"settingsPane": "general"},
//   {"wait": 1},
//   {"capture": {"name": "settings-general", "window": "settings"}},
//   {"axdump": {"name": "settings-general", "window": "settings"}},
//   {"quit": true}
// ]
//
// Captures use ScreenCaptureKit's current-process content (no Screen Recording permission for the app's own
// windows) and fall back to `NSView.cacheDisplay`. When ScreenCaptureKit fails anyway (error -3811 when the launching
// process has no Screen Recording permission; logged as "captureFallback"), set CODOMETER_DEBUG_CAPTURE=view to draw
// every frame synchronously at the moment it is due. Such draws show content and the rim but not Liquid Glass (glass
// comes out empty, dark glass as its refraction map), so check content with "surface": "solid". Each frame appends one
// JSON line to `frames.jsonl`: time since start, step, name, frame index, file, window, panel frame, island shape frame
// (screen coordinates), measured rail and deck sizes, isExpanded, isPinned, edge, anchor, style, whether the real pointer
// is over the island, the first 8 characters of the selected account id, the interface language, and the fields the
// domain handlers add.

/// Entry point of the debug scenario harness.
@MainActor
enum DebugScenario {
    static let scenarioVariable = "CODOMETER_DEBUG_SCENARIO"
    static let outputVariable = "CODOMETER_DEBUG_OUT"

    private static var runner: DebugScenarioRunner?

    /// Starts the scenario named by `CODOMETER_DEBUG_SCENARIO`, if any. Call once after launch.
    static func startIfRequested(controller: AppController) {
        let environment = ProcessInfo.processInfo.environment
        guard runner == nil, let scenarioPath = environment[scenarioVariable] else { return }
        guard let outputPath = environment[outputVariable] else {
            AppLog.interface.error("debug scenario: \(outputVariable, privacy: .public) is not set")
            return
        }
        do {
            let steps = try DebugScenarioScript.load(path: scenarioPath)
            let output = try DebugOutput(directoryPath: outputPath)
            let started = DebugScenarioRunner(context: DebugContext(controller: controller, output: output), steps: steps)
            runner = started
            started.start()
            AppLog.interface.notice("debug scenario started: \(steps.count, privacy: .public) steps")
        } catch {
            AppLog.interface.error("debug scenario not started: \(String(describing: error), privacy: .public)")
        }
    }

    /// The step keys of the scenario the environment names, e.g. to tell whether it has an `onboarding` step; empty
    /// without a scenario or when it cannot be read.
    static func requestedStepKeys(environment: [String: String] = ProcessInfo.processInfo.environment) -> Set<String> {
        guard let path = environment[scenarioVariable], let steps = try? DebugScenarioScript.load(path: path) else { return [] }
        return Set(steps.map(\.key))
    }

    /// Offers a step no generic case handles to each domain handler in turn; `false` when none knows the key.
    static func handleDomainStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        if try await handleIslandStep(key, value, context) { return true }
        if try await handleVisualsStep(key, value, context) { return true }
        if try await handleCardStep(key, value, context) { return true }
        if try await handleReliabilityStep(key, value, context) { return true }
        if try await handleSettingsStep(key, value, context) { return true }
        if try await handleOnboardingStep(key, value, context) { return true }
        if try await handleStatusStep(key, value, context) { return true }
        return false
    }

    /// The fields every domain adds to `capture` and `trace` lines (a later domain wins on a shared name).
    static func domainTraceFields(_ context: DebugContext) -> [String: Any] {
        var fields: [String: Any] = [:]
        let parts = [
            islandTraceFields(context),
            visualsTraceFields(context),
            cardTraceFields(context),
            reliabilityTraceFields(context),
            settingsTraceFields(context),
            onboardingTraceFields(context),
            statusTraceFields(context),
        ]
        for part in parts {
            fields.merge(part) { _, new in new }
        }
        return fields
    }
}

struct DebugScenarioError: Error, CustomStringConvertible {
    let description: String
}

/// Checked readers for step arguments (JSON values from `JSONSerialization`).
enum DebugValue {
    /// A JSON `true` or `false` (not a number).
    static func bool(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A finite JSON number (not a boolean).
    static func number(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    static func string(_ value: Any) -> String? {
        value as? String
    }

    static func object(_ value: Any) -> [String: Any]? {
        value as? [String: Any]
    }

    /// `[x, y]`.
    static func point(_ value: Any) -> CGPoint? {
        guard let pair = value as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// JSON `null`.
    static func isNull(_ value: Any) -> Bool {
        value is NSNull
    }
}

enum DebugStep: Sendable, Equatable {
    /// A JSON object of setting overrides.
    case settings(Data)
    /// A deck page's raw value.
    case page(String)
    /// An `AnalyticsRange` raw value.
    case range(String)
    case wait(TimeInterval)
    case monitor(TimeInterval)
    /// `nil` follows the system setting again.
    case reduceMotion(Bool?)
    case capture(name: String, frames: Int, interval: TimeInterval, window: String)
    /// Geometry lines only, no images.
    case trace(name: String, frames: Int, interval: TimeInterval, window: String)
    case language(LanguagePreference)
    case settingsPane(SettingsPane)
    case axdump(name: String, window: String)
    case fixture(DebugFixtureName)
    case popover(Bool)
    case quit
    /// A key for the domain handlers, with its value as JSON (wrapped in a one-element array).
    case domain(key: String, value: Data)

    /// The step's key in the scenario file.
    var key: String {
        switch self {
        case .settings: "settings"
        case .page: "page"
        case .range: "range"
        case .wait: "wait"
        case .monitor: "monitor"
        case .reduceMotion: "reduceMotion"
        case .capture: "capture"
        case .trace: "trace"
        case .language: "language"
        case .settingsPane: "settingsPane"
        case .axdump: "axdump"
        case .fixture: "fixture"
        case .popover: "popover"
        case .quit: "quit"
        case .domain(let key, _): key
        }
    }

    var label: String {
        switch self {
        case .settings: "settings"
        case .page(let name): "page:\(name)"
        case .range(let name): "range:\(name)"
        case .wait: "wait"
        case .monitor: "monitor"
        case .reduceMotion(let value): "reduceMotion:\(value.map(String.init(describing:)) ?? "system")"
        case .capture(let name, _, _, _): "capture:\(name)"
        case .trace(let name, _, _, _): "trace:\(name)"
        case .language(let preference): "language:\(preference.rawValue)"
        case .settingsPane(let pane): "settingsPane:\(pane.rawValue)"
        case .axdump(let name, _): "axdump:\(name)"
        case .fixture(let name): "fixture:\(name.rawValue)"
        case .popover(let shown): shown ? "popover" : "popoverClose"
        case .quit: "quit"
        case .domain(let key, _): key
        }
    }
}

/// Strict parsing of scenario files.
enum DebugScenarioScript {
    static let maximumFileSize = 256 * 1_024
    static let maximumSteps = 500
    static let waitRange: ClosedRange<Double> = 0...60
    static let frameRange: ClosedRange<Int> = 1...120
    static let intervalRange: ClosedRange<Double> = 0...5

    static func load(path: String) throws -> [DebugStep] {
        guard path.hasPrefix("/") else { throw DebugScenarioError(description: "scenario path must be absolute") }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DebugScenarioError(description: "scenario is not a regular file") }
        guard let size = values.fileSize, size <= maximumFileSize else { throw DebugScenarioError(description: "scenario file is too large") }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> [DebugStep] {
        let root = try JSONSerialization.jsonObject(with: data)
        let list: [Any]
        if let array = root as? [Any] {
            list = array
        } else if let object = root as? [String: Any], object.count == 1, let steps = object["steps"] as? [Any] {
            list = steps
        } else {
            throw DebugScenarioError(description: "scenario must be an array of steps")
        }
        guard list.count <= maximumSteps else { throw DebugScenarioError(description: "too many steps") }
        return try list.enumerated().map { index, value in try step(value, index: index) }
    }

    private static func step(_ value: Any, index: Int) throws -> DebugStep {
        guard let object = value as? [String: Any], object.count == 1, let (key, argument) = object.first else {
            throw DebugScenarioError(description: "step \(index): expected an object with one key")
        }
        func fail(_ reason: String) -> DebugScenarioError {
            DebugScenarioError(description: "step \(index) (\(key)): \(reason)")
        }
        switch key {
        case "settings":
            guard let patch = argument as? [String: Any] else { throw fail("expected an object") }
            return .settings(try JSONSerialization.data(withJSONObject: patch))
        case "quit":
            guard DebugValue.bool(argument) == true else { throw fail("expected true") }
            return .quit
        case "popover":
            guard let shown = DebugValue.bool(argument) else { throw fail("expected true or false") }
            return .popover(shown)
        case "page":
            guard let name = argument as? String, DebugDeckCommands.pageNames.contains(name) else {
                throw fail("expected one of \(DebugDeckCommands.pageNames.sorted())")
            }
            return .page(name)
        case "range":
            guard let name = argument as? String, DebugDeckCommands.rangeNames.contains(name) else {
                throw fail("expected one of \(DebugDeckCommands.rangeNames.sorted())")
            }
            return .range(name)
        case "language":
            guard let raw = argument as? String, let preference = LanguagePreference(rawValue: raw) else {
                throw fail("expected \"en\", \"ru\" or \"system\"")
            }
            return .language(preference)
        case "settingsPane":
            guard let raw = argument as? String, let pane = SettingsPane(rawValue: raw) else {
                throw fail("expected one of \(SettingsPane.allCases.map(\.rawValue))")
            }
            return .settingsPane(pane)
        case "fixture":
            guard let raw = argument as? String, let name = DebugFixtureName(rawValue: raw) else {
                throw fail("expected one of \(DebugFixtureName.allCases.map(\.rawValue))")
            }
            return .fixture(name)
        case "reduceMotion":
            if let text = argument as? String, text == "system" { return .reduceMotion(nil) }
            guard let flag = DebugValue.bool(argument) else { throw fail("expected true, false or \"system\"") }
            return .reduceMotion(flag)
        case "monitor", "wait":
            guard let seconds = DebugValue.number(argument), waitRange.contains(seconds) else {
                throw fail("expected seconds in 0…60")
            }
            return key == "wait" ? .wait(seconds) : .monitor(seconds)
        case "capture", "trace":
            guard let capture = argument as? [String: Any], Set(capture.keys).isSubset(of: ["name", "frames", "interval", "window"]) else {
                throw fail("expected {name, frames, interval, window}")
            }
            guard let name = capture["name"] as? String, isSafeName(name) else {
                throw fail("name must be 1–64 characters of A–Z, a–z, 0–9, '.', '_' or '-'")
            }
            let frames = (capture["frames"] as? NSNumber)?.intValue ?? 1
            let interval = (capture["interval"] as? NSNumber)?.doubleValue ?? 0
            guard frameRange.contains(frames) else { throw fail("frames must be in 1…120") }
            guard interval.isFinite, intervalRange.contains(interval) else { throw fail("interval must be in 0…5 s") }
            let window = try windowName(capture["window"], fail: fail)
            return key == "trace"
                ? .trace(name: name, frames: frames, interval: interval, window: window)
                : .capture(name: name, frames: frames, interval: interval, window: window)
        case "axdump":
            guard let dump = argument as? [String: Any], Set(dump.keys).isSubset(of: ["name", "window"]) else {
                throw fail("expected {name, window}")
            }
            guard let name = dump["name"] as? String, isSafeName(name) else {
                throw fail("name must be 1–64 characters of A–Z, a–z, 0–9, '.', '_' or '-'")
            }
            return .axdump(name: name, window: try windowName(dump["window"], fail: fail))
        default:
            // Validated by the domain handler that takes the key, when the step runs.
            return .domain(key: key, value: try JSONSerialization.data(withJSONObject: [argument]))
        }
    }

    private static func windowName(_ value: Any?, fail: (String) -> DebugScenarioError) throws -> String {
        guard let value else { return DebugWindows.island }
        guard let name = value as? String, DebugWindows.names.contains(name) else {
            throw fail("window must be one of \(DebugWindows.names.sorted())")
        }
        return name
    }

    static func isSafeName(_ name: String) -> Bool {
        guard (1...64).contains(name.count), !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-")
        }
    }

    /// The value a `.domain` step carries.
    static func domainValue(_ data: Data) throws -> Any {
        guard let wrapped = try JSONSerialization.jsonObject(with: data) as? [Any], let value = wrapped.first else {
            throw DebugScenarioError(description: "unreadable step value")
        }
        return value
    }

    /// Applies a settings patch through the settings' own `Codable` validation.
    static func applying(
        _ patchData: Data,
        to appearance: AppearanceSettings,
        general: GeneralSettings
    ) throws -> (appearance: AppearanceSettings, general: GeneralSettings) {
        guard var patch = try JSONSerialization.jsonObject(with: patchData) as? [String: Any] else {
            throw DebugScenarioError(description: "settings: expected an object")
        }
        var appearancePatch = try nested(patch.removeValue(forKey: "appearance"), name: "appearance")
        var generalPatch = try nested(patch.removeValue(forKey: "general"), name: "general")
        let appearanceKeys = try keys(of: appearance).union(["railGroupFilter"])
        let generalKeys = try keys(of: general)
        for (key, value) in patch {
            if appearanceKeys.contains(key) {
                appearancePatch[key] = value
            } else if generalKeys.contains(key) {
                generalPatch[key] = value
            } else {
                throw DebugScenarioError(description: "settings: unknown key \(key)")
            }
        }
        if let unknown = appearancePatch.keys.first(where: { !appearanceKeys.contains($0) }) {
            throw DebugScenarioError(description: "settings.appearance: unknown key \(unknown)")
        }
        if let unknown = generalPatch.keys.first(where: { !generalKeys.contains($0) }) {
            throw DebugScenarioError(description: "settings.general: unknown key \(unknown)")
        }
        return (try merged(appearance, with: appearancePatch), try merged(general, with: generalPatch))
    }

    private static func nested(_ value: Any?, name: String) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let object = value as? [String: Any] else {
            throw DebugScenarioError(description: "settings.\(name): expected an object")
        }
        return object
    }

    private static func keys(of value: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        return Set(object.map { Array($0.keys) } ?? [])
    }

    private static func merged<Value: Codable>(_ value: Value, with patch: [String: Any]) throws -> Value {
        guard !patch.isEmpty else { return value }
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else {
            throw DebugScenarioError(description: "settings: could not encode current values")
        }
        object.merge(patch) { _, new in new }
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

/// What a step handler works with: the app, the output, and background work the runner waits for.
@MainActor
final class DebugContext {
    let controller: AppController
    let output: DebugOutput
    /// The index of the step running now.
    fileprivate(set) var step = 0
    fileprivate let clock = ContinuousClock()
    private let startedAt: ContinuousClock.Instant
    private var pending: [Task<Void, Never>] = []

    init(controller: AppController, output: DebugOutput) {
        self.controller = controller
        self.output = output
        startedAt = clock.now
    }

    var store: TrackerStore { controller.store }
    var island: IslandController { controller.island }

    /// Seconds since the scenario was created.
    var elapsed: Double {
        let duration = clock.now - startedAt
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Appends a `frames.jsonl` line with `t` and `step` added.
    func log(_ fields: [String: Any]) {
        var line = fields
        line["t"] = elapsed
        line["step"] = step
        output.appendLine(line)
    }

    /// Runs work in the background (a drag, a capture); `quit` and capture steps wait for it to finish.
    func background(_ operation: @escaping @MainActor () async -> Void) {
        pending.append(Task { @MainActor in
            await operation()
        })
    }

    /// The selected Settings pane drawn on its own, for captures and dumps of "settings" (see `SettingsPaneCaptureView`).
    private(set) var settingsStandIn: NSWindow?

    /// Shows `pane` in the stand-in: a borderless, never-key window of the Settings detail size, placed far outside
    /// every display, following the store's language like the real window.
    func showSettingsStandIn(_ pane: SettingsPane) {
        let host = NSHostingView(rootView: SettingsPaneCaptureView(store: store, pane: pane))
        let window = settingsStandIn ?? NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: 700, height: 660),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        settingsStandIn = window
    }

    /// Waits for every background operation started so far.
    func finishBackground() async {
        while !pending.isEmpty {
            let tasks = pending
            pending.removeAll()
            for task in tasks {
                await task.value
            }
        }
    }
}

/// The app's windows by name, for capture, trace and axdump steps. Weak: a closed window drops out on its own.
@MainActor
enum DebugWindows {
    nonisolated static let island = "island"
    nonisolated static let card = "card"
    nonisolated static let popover = "popover"
    nonisolated static let settings = "settings"
    nonisolated static let onboarding = "onboarding"
    nonisolated static let names: Set<String> = [island, card, popover, settings, onboarding]

    private final class WeakWindow {
        weak var window: NSWindow?

        init(_ window: NSWindow) {
            self.window = window
        }
    }

    private static var windows: [String: WeakWindow] = [:]

    /// Registers (or replaces) the window shown under `name`.
    static func register(_ window: NSWindow, name: String) {
        windows[name] = WeakWindow(window)
    }

    static func window(named name: String) -> NSWindow? {
        windows[name]?.window
    }
}

/// Runs the steps and records captures.
@MainActor
final class DebugScenarioRunner {
    private let context: DebugContext
    private let steps: [DebugStep]
    private var task: Task<Void, Never>?

    init(context: DebugContext, steps: [DebugStep]) {
        self.context = context
        self.steps = steps
    }

    private var controller: AppController { context.controller }
    private var island: IslandController { context.island }
    private var store: TrackerStore { context.store }
    private var output: DebugOutput { context.output }
    private var elapsed: Double { context.elapsed }

    func start() {
        task = Task { [weak self] in
            // Let the island measure itself and settle after launch.
            try? await Task.sleep(for: .seconds(1))
            await self?.run()
        }
    }

    private func run() async {
        for (index, step) in steps.enumerated() {
            context.step = index
            do {
                try await perform(step, index: index)
            } catch {
                output.appendLine(["t": elapsed, "step": index, "action": step.label, "error": String(describing: error)])
                AppLog.interface.error("debug step \(index, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        await context.finishBackground()
        output.appendLine(["t": elapsed, "action": "done"])
    }

    private func perform(_ step: DebugStep, index: Int) async throws {
        switch step {
        case .settings(let patch):
            let current = island.debugSettings
            var general = current.general
            if island.debugGeneralOverride == nil, controller.directories.isIsolated {
                // An isolated run registers no global shortcut unless the scenario sets one explicitly.
                general.globalShortcut = .off
            }
            let updated = try DebugScenarioScript.applying(patch, to: current.appearance, general: general)
            island.debugApply(appearance: updated.appearance, general: updated.general)
            // The floating card keeps its own in-memory override, so a generic patch (scale, theme, size) reaches
            // whichever surface is on screen.
            controller.presentation.card?.debugApply(appearance: updated.appearance)
            controller.applyShortcut()
            // The rail and the deck read the group filter from the store (like the deck header, which sets it there):
            // mirror it in memory, never saved.
            let filter = updated.appearance.railGroupFilter
            if store.settings.appearance.railGroupFilter != filter {
                store.debugOverrideSettings { $0.appearance.railGroupFilter = filter }
            }
        case .fixture(let name):
            let fixture = try DebugFixtures.make(name, base: store.settings)
            controller.debugInstallFixture(fixture)
            output.appendLine(["t": elapsed, "step": index, "action": "fixture", "name": name.rawValue, "accounts": fixture.state.accounts.count])
        case .language(let preference):
            store.debugOverrideSettings { $0.general.language = preference }
            controller.statusItem.update()
        case .settingsPane(let pane):
            controller.settingsWindow.show(pane: pane)
            context.showSettingsStandIn(pane)
        case .popover(let shown):
            controller.statusItem.debugSetPopoverShown(shown)
        case .page(let name):
            NotificationCenter.default.post(name: DebugDeckCommands.showPage, object: nil, userInfo: [DebugDeckCommands.valueKey: name])
        case .range(let name):
            NotificationCenter.default.post(name: DebugDeckCommands.showRange, object: nil, userInfo: [DebugDeckCommands.valueKey: name])
        case .wait(let seconds):
            try await Task.sleep(for: .milliseconds(Int((seconds * 1_000).rounded())))
        case .monitor(let seconds):
            startMonitor(seconds: seconds, step: index)
        case .reduceMotion(let value):
            Motion.reducesMotionOverride = value
        case .capture(let name, let frames, let interval, let window):
            await capture(name: name, frames: frames, interval: interval, window: window, step: index)
        case .trace(let name, let frames, let interval, let window):
            await trace(name: name, frames: frames, interval: interval, window: window, step: index)
        case .axdump(let name, let window):
            try await axdump(name: name, window: window, step: index)
        case .quit:
            await context.finishBackground()
            output.appendLine(["t": elapsed, "action": "quit"])
            NSApp.terminate(nil)
        case .domain(let key, let data):
            let value = try DebugScenarioScript.domainValue(data)
            guard try await DebugScenario.handleDomainStep(key, value, context) else {
                throw DebugScenarioError(description: "unknown step \(key)")
            }
        }
    }

    /// Wakes on the main actor every 4 ms and logs late wake-ups, which show up as dropped animation frames.
    private func startMonitor(seconds: TimeInterval, step: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = context.clock
            let begin = clock.now
            var last = begin
            var worst = 0.0
            var stalls = 0
            var late = 0
            var blocked = 0.0
            while clock.now - begin < .milliseconds(Int(seconds * 1_000)) {
                try? await Task.sleep(for: .milliseconds(4))
                let now = clock.now
                let gap = now - last
                let ms = Double(gap.components.seconds) * 1_000 + Double(gap.components.attoseconds) / 1e15
                last = now
                worst = max(worst, ms)
                if ms > 12 {
                    // Longer than a 120 Hz frame and a half: at least one frame could not be drawn on time.
                    late += 1
                    blocked += ms
                }
                if ms > 24 {
                    stalls += 1
                    output.appendLine(["t": elapsed, "step": step, "action": "stall", "ms": ms.rounded()])
                }
            }
            output.appendLine(["t": elapsed, "step": step, "action": "monitorDone", "stalls": stalls, "late": late, "blockedMs": blocked.rounded(), "worstMs": worst.rounded()])
        }
    }

    /// The window a capture, trace or axdump step names; the island's panel is always there.
    private func window(named name: String) -> NSWindow? {
        name == DebugWindows.island ? island.debugPanel : DebugWindows.window(named: name)
    }

    private func capture(name: String, frames: Int, interval: TimeInterval, window windowName: String, step: Int) async {
        guard let window = window(named: windowName), window.isVisible else {
            output.appendLine(["t": elapsed, "step": step, "action": "captureSkipped", "name": name, "window": windowName, "error": "window not open"])
            return
        }
        var target = window
        let first = island.debugGeometry
        // One fixed screen region per capture step (the island: rail and deck with their margins; other windows: their
        // frame), resolved once, so every frame of a sequence has the same size and is taken the moment it is due.
        let region = windowName == DebugWindows.island ? first.captureRegion : window.frame
        let session = DebugCaptureSession()
        var usesScreenCapture = false
        // CODOMETER_DEBUG_CAPTURE=view|layer skips ScreenCaptureKit (e.g. when the process tree has no Screen
        // Recording permission) and draws the window synchronously at the moment each frame is due.
        let method = ProcessInfo.processInfo.environment["CODOMETER_DEBUG_CAPTURE"] ?? "auto"
        if method != "view", method != "layer", let region, let primary = NSScreen.screens.first {
            let global = CGRect(x: region.minX, y: primary.frame.maxY - region.maxY, width: region.width, height: region.height)
            usesScreenCapture = await session.prepare(
                windowID: CGWindowID(max(0, target.windowNumber)),
                region: global,
                scale: target.backingScaleFactor
            )
            if !usesScreenCapture {
                output.appendLine(["t": elapsed, "action": "capturePrepareFailed", "name": name, "error": await session.lastError ?? "window or region not found"])
            }
        }
        // View and layer draws of the Settings window come out empty (its split-view columns): draw the pane instead.
        let usesStandIn = !usesScreenCapture && windowName == DebugWindows.settings
        if usesStandIn, let standIn = context.settingsStandIn {
            target = standIn
        }
        let begin = context.clock.now
        for frame in 0..<frames {
            let due = begin + .milliseconds(Int((interval * 1_000 * Double(frame)).rounded()))
            try? await context.clock.sleep(until: due)
            // Geometry is recorded at the moment the frame is requested.
            let file = "\(name)-\(String(format: "%03d", frame)).png"
            output.appendLine(geometryLine(
                action: "capture",
                name: name,
                frame: frame,
                step: step,
                window: windowName,
                extra: [
                    "file": file,
                    "capture": usesScreenCapture ? "screencapturekit" : method == "layer" ? "layerRender" : "cacheDisplay",
                    "standIn": usesStandIn,
                    "region": region.map(Self.json) ?? NSNull(),
                ]
            ))
            guard usesScreenCapture else {
                output.write(method == "layer" ? Self.layerPNG(of: target) : Self.cachedDisplayPNG(of: target), named: file)
                continue
            }
            context.background { [weak self] in
                let png = await session.capturePNG()
                guard let self else { return }
                if png == nil {
                    output.appendLine(["t": elapsed, "action": "captureFallback", "file": file, "error": await session.lastError ?? "unknown"])
                }
                output.write(png ?? Self.cachedDisplayPNG(of: target), named: file)
            }
        }
        // Frames are requested on schedule without waiting for each other; the step ends once all have landed,
        // so the next step cannot change the window before the last image is taken.
        await context.finishBackground()
    }

    /// Records the geometry `frames` times, `interval` apart, without taking images.
    private func trace(name: String, frames: Int, interval: TimeInterval, window: String, step: Int) async {
        let begin = context.clock.now
        for frame in 0..<frames {
            try? await context.clock.sleep(until: begin + .milliseconds(Int((interval * 1_000 * Double(frame)).rounded())))
            output.appendLine(geometryLine(action: "trace", name: name, frame: frame, step: step, window: window, extra: [:]))
        }
    }

    /// Writes the named window's accessibility tree to `ax-<name>.json`.
    private func axdump(name: String, window windowName: String, step: Int) async throws {
        guard var target = window(named: windowName), target.isVisible else {
            throw DebugScenarioError(description: "axdump: window \(windowName) is not open")
        }
        // The Settings window exposes its panes to accessibility lazily; dump the selected pane's stand-in.
        let usesStandIn = windowName == DebugWindows.settings && context.settingsStandIn != nil
        if usesStandIn, let standIn = context.settingsStandIn {
            target = standIn
        }
        guard let data = DebugAccessibilityDump.json(of: target) else {
            throw DebugScenarioError(description: "axdump: window \(windowName) is not in the accessibility tree")
        }
        let file = "ax-\(name).json"
        output.write(data, named: file)
        output.appendLine(["t": elapsed, "step": step, "action": "axdump", "name": name, "window": windowName, "file": file, "standIn": usesStandIn])
    }

    /// One `frames.jsonl` line with the island's geometry and state right now, plus the domains' fields.
    private func geometryLine(action: String, name: String, frame: Int, step: Int, window: String, extra: [String: Any]) -> [String: Any] {
        let geometry = island.debugGeometry
        var line: [String: Any] = [
            "t": elapsed,
            "step": step,
            "action": action,
            "name": name,
            "frame": frame,
            "window": window,
            "panel": Self.json(geometry.panelFrame),
            "island": geometry.islandFrame.map(Self.json) ?? NSNull(),
            "rail": Self.json(geometry.sizes.rail),
            "deck": Self.json(geometry.sizes.deck),
            "isExpanded": geometry.isExpanded,
            "isPinned": geometry.isPinned,
            "isHovered": geometry.isHovered,
            "prewarmsDeck": geometry.prewarmsDeck,
            "reducesMotion": Motion.reducesMotion,
            "edge": geometry.edge.rawValue,
            "anchor": String(describing: geometry.anchor),
            "style": geometry.style.rawValue,
            // Real pointer input can change the deck (hovering a dial selects its account), so record it.
            "pointerInIsland": geometry.islandFrame.map { $0.contains(NSEvent.mouseLocation) } ?? false,
            "selectedAccount": island.model.selectedAccountID.map { String($0.rawValue.uuidString.prefix(8)) } ?? NSNull(),
            "language": store.localizer.language.rawValue,
        ]
        if window != DebugWindows.island, let target = self.window(named: window) {
            line["windowFrame"] = Self.json(target.frame)
        }
        line.merge(DebugScenario.domainTraceFields(context)) { _, new in new }
        line.merge(extra) { _, new in new }
        return line
    }

    private static func cachedDisplayPNG(of window: NSWindow) -> Data? {
        guard let view = window.contentView, view.bounds.width > 0, view.bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Renders the window's layer tree (presentation layers, so running Core Animation is included).
    private static func layerPNG(of window: NSWindow) -> Data? {
        guard let view = window.contentView, let layer = view.layer, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let scale = window.backingScaleFactor
        let width = Int((view.bounds.width * scale).rounded())
        let height = Int((view.bounds.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !view.isFlipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.scaleBy(x: scale, y: scale)
        (layer.presentation() ?? layer).render(in: context)
        guard let image = context.makeImage() else { return nil }
        return DebugCaptureSession.png(image)
    }

    private static func json(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private static func json(_ size: CGSize) -> [String: Double] {
        ["width": size.width, "height": size.height]
    }
}

/// The window number of a top-level accessibility element (HIServices SPI, used by debug builds only).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ window: UnsafeMutablePointer<CGWindowID>) -> AXError

/// The accessibility tree of one of the app's own windows as VoiceOver reads it, for `axdump`.
///
/// Read through the accessibility API (`AXUIElement`) on this process, the way assistive apps do: SwiftUI creates its
/// accessibility elements for those requests, which in-process `NSAccessibility` calls do not reliably trigger. Requests
/// to one's own process are answered in place, on the calling thread, and run SwiftUI code, so the walk runs on the main
/// actor. No permission is needed to read one's own process.
@MainActor
enum DebugAccessibilityDump {
    nonisolated static let maximumDepth = 40
    /// At most this many elements are written; a larger tree is cut off (`"truncated": true` on the root).
    nonisolated static let maximumNodes = 3_000
    /// The walk stops descending after this long (`"truncated": true`), so a slow tree never stalls a scenario.
    nonisolated static let timeBudget: Duration = .seconds(20)

    /// Roles whose in-process elements take a press (the accessibility API reports actions itself).
    private static let pressableRoles: Set<String> = [
        kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXDisclosureTriangleRole,
        kAXMenuItemRole, "AXLink",
    ]

    /// Attributes read per element, in one request.
    private static let attributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute,
        kAXHelpAttribute, kAXIdentifierAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
    ]

    /// The tree of this process's top-level accessibility element for `window` (matched by window number, else by frame),
    /// as pretty-printed JSON; `nil` when no element matches.
    static func json(of window: NSWindow) -> Data? {
        let application = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(application, 1)
        let candidates = (copy(application, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            + (copy(application, kAXWindowsAttribute) as? [AXUIElement] ?? [])
        let number = CGWindowID(max(0, window.windowNumber))
        let frame = accessibilityFrame(of: window)
        let byNumber = candidates.first { element in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(element, &id) == .success && id == number
        }
        let byFrame = candidates.first { element in
            guard let found = rect(values(of: element)) else { return false }
            return abs(found.minX - frame.minX) < 2 && abs(found.minY - frame.minY) < 2
                && abs(found.width - frame.width) < 2 && abs(found.height - frame.height) < 2
        }
        var walk = Walk(deadline: ContinuousClock.now + timeBudget)
        var tree: [String: Any]
        if let element = byNumber ?? byFrame {
            tree = walk.node(.remote(element), depth: 0)
        } else {
            // The application's window list is fixed at its first accessibility request, so a window opened later
            // is walked from its own object; the request above has already switched SwiftUI's accessibility on.
            tree = walk.node(.local(window), depth: 0)
            tree["source"] = "inProcess"
        }
        tree["truncated"] = walk.truncated
        return try? JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
    }

    /// Converts an AppKit window frame (bottom-left origin) to the accessibility API's top-left coordinates.
    static func accessibilityFrame(of window: NSWindow) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: window.frame.minX, y: primaryHeight - window.frame.maxY, width: window.frame.width, height: window.frame.height)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    /// `attributes` of one element in a single request; attributes the element lacks are left out.
    private static func values(of element: AXUIElement) -> [String: Any] {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &result) == .success,
              let list = result as? [Any], list.count == attributes.count
        else { return [:] }
        var values: [String: Any] = [:]
        for (name, value) in zip(attributes, list) {
            // A missing attribute comes back as an AXValue holding an error.
            if CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID(), AXValueGetType(unsafeDowncast(value as AnyObject, to: AXValue.self)) == .axError {
                continue
            }
            values[name] = value
        }
        return values
    }

    private static func rect(_ values: [String: Any]) -> CGRect? {
        guard let positionValue = values[kAXPositionAttribute], let sizeValue = values[kAXSizeAttribute],
              CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue as AnyObject, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue as AnyObject, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func text(_ value: Any?) -> Any {
        switch value {
        case let string as String: string.isEmpty ? NSNull() : string
        case let number as NSNumber: number.stringValue
        case let attributed as NSAttributedString: attributed.string.isEmpty ? NSNull() : attributed.string
        default: NSNull()
        }
    }

    /// An element reached through the accessibility API, or an object of this process walked directly.
    private enum Element {
        case remote(AXUIElement)
        case local(NSObject)
    }

    /// Reads an in-process object's accessibility attributes: through `NSAccessibilityProtocol` when it conforms (AppKit
    /// views and windows), otherwise by Key-Value Coding of the same getters (SwiftUI's nodes), only for getters it has.
    private static func localValues(of object: NSObject) -> [String: Any] {
        func get(_ getter: String, key: String? = nil) -> Any? {
            guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
            return object.value(forKey: key ?? getter)
        }
        var values: [String: Any] = [:]
        if let item = object as? any NSAccessibilityProtocol {
            values[kAXRoleAttribute] = item.accessibilityRole()?.rawValue
            values[kAXSubroleAttribute] = item.accessibilitySubrole()?.rawValue
            values[kAXDescriptionAttribute] = item.accessibilityLabel()
            values[kAXTitleAttribute] = item.accessibilityTitle()
            values[kAXValueAttribute] = item.accessibilityValue()
            values[kAXHelpAttribute] = item.accessibilityHelp()
            values[kAXIdentifierAttribute] = item.accessibilityIdentifier()
            values["frame"] = item.accessibilityFrame()
            values["actions"] = (item.accessibilityCustomActions() ?? []).map(\.name)
            values[kAXChildrenAttribute] = item.accessibilityChildren()
        } else {
            values[kAXRoleAttribute] = get("accessibilityRole")
            values[kAXSubroleAttribute] = get("accessibilitySubrole")
            values[kAXDescriptionAttribute] = get("accessibilityLabel")
            values[kAXTitleAttribute] = get("accessibilityTitle")
            values[kAXValueAttribute] = get("accessibilityValue")
            values[kAXHelpAttribute] = get("accessibilityHelp")
            values[kAXIdentifierAttribute] = get("accessibilityIdentifier")
            values["frame"] = (get("accessibilityFrame") as? NSValue)?.rectValue
            values["actions"] = (get("accessibilityCustomActions") as? [NSAccessibilityCustomAction] ?? []).map(\.name)
            values[kAXChildrenAttribute] = get("accessibilityChildren")
        }
        return values
    }

    /// One walk's budgets.
    @MainActor
    private struct Walk {
        let deadline: ContinuousClock.Instant
        var remaining: Int
        var truncated = false
        /// Keeps in-process elements alive until the walk ends, so none is freed and its address reused mid-walk.
        var retained: [ObjectIdentifier: NSObject] = [:]

        init(deadline: ContinuousClock.Instant) {
            self.deadline = deadline
            remaining = DebugAccessibilityDump.maximumNodes
        }

        mutating func node(_ element: Element, depth: Int) -> [String: Any] {
            remaining -= 1
            let values: [String: Any]
            let frame: CGRect?
            var actions: [String]
            let children: [Element]
            switch element {
            case .remote(let item):
                values = DebugAccessibilityDump.values(of: item)
                frame = rect(values)
                var names: CFArray?
                actions = AXUIElementCopyActionNames(item, &names) == .success ? (names as? [String] ?? []) : []
                children = (values[kAXChildrenAttribute] as? [AXUIElement] ?? []).map(Element.remote)
            case .local(let object):
                retained[ObjectIdentifier(object)] = object
                values = localValues(of: object)
                frame = values["frame"] as? CGRect
                actions = values["actions"] as? [String] ?? []
                if let role = values[kAXRoleAttribute] as? String, pressableRoles.contains(role) {
                    actions.insert(NSAccessibility.Action.press.rawValue, at: 0)
                }
                children = (values[kAXChildrenAttribute] as? [Any] ?? []).compactMap { child in
                    guard let object = child as? NSObject, retained[ObjectIdentifier(object)] == nil else { return nil }
                    return .local(object)
                }
            }
            var fields: [String: Any] = [
                "role": text(values[kAXRoleAttribute]),
                "subrole": text(values[kAXSubroleAttribute]),
                "label": text(values[kAXDescriptionAttribute]),
                "title": text(values[kAXTitleAttribute]),
                "value": text(values[kAXValueAttribute]),
                "help": text(values[kAXHelpAttribute]),
                "identifier": text(values[kAXIdentifierAttribute]),
                "actions": actions,
            ]
            if let frame {
                fields["frame"] = ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            }
            var nodes: [[String: Any]] = []
            for child in children {
                guard depth < maximumDepth, remaining > 0, ContinuousClock.now < deadline else {
                    truncated = true
                    break
                }
                nodes.append(node(child, depth: depth + 1))
            }
            fields["children"] = nodes
            return fields
        }
    }
}

extension AppController {
    /// Replaces accounts, state and analytics with the fixture's, keeping appearance, alerts and general settings.
    func debugInstallFixture(_ fixture: DebugFixture) {
        debugFixture = fixture
        store.debugInstallFixture(state: fixture.state, settings: fixture.settings, now: fixture.now)
        store.celebrate(fixture.resets, now: fixture.now)
        applySurfaces()
        statusItem.update()
    }
}

/// ScreenCaptureKit captures of a fixed screen region that include only one of this process's windows.
/// Current-process content needs no Screen Recording permission.
actor DebugCaptureSession {
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    /// Held here because the configuration only keeps an unowned reference to its background colour.
    private let transparent = CGColor(gray: 0, alpha: 0)
    /// The last ScreenCaptureKit failure, for the log.
    private(set) var lastError: String?

    /// `region` uses Core Graphics global coordinates (top-left origin), in points.
    func prepare(windowID: CGWindowID, region: CGRect, scale: CGFloat) async -> Bool {
        guard windowID != 0, region.width > 0, region.height > 0 else { return false }
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return false }
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let center = CGPoint(x: region.midX, y: region.midY)
            let windowOnly = ProcessInfo.processInfo.environment["CODOMETER_DEBUG_CAPTURE"] == "window"
            if !windowOnly, let display = content.displays.first(where: { $0.frame.contains(center) }) {
                configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                configuration.width = max(1, Int((region.width * scale).rounded()))
                configuration.height = max(1, Int((region.height * scale).rounded()))
                configuration.backgroundColor = transparent
                filter = SCContentFilter(display: display, including: [window])
            } else {
                configuration.width = max(1, Int((window.frame.width * scale).rounded()))
                configuration.height = max(1, Int((window.frame.height * scale).rounded()))
                configuration.ignoreShadowsSingleWindow = true
                filter = SCContentFilter(desktopIndependentWindow: window)
            }
            self.configuration = configuration
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    func capturePNG() async -> Data? {
        guard let filter, let configuration else { return nil }
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return Self.png(image)
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// The output directory: PNG captures, accessibility dumps and `frames.jsonl`.
@MainActor
final class DebugOutput {
    let directory: URL
    private let log: URL

    init(directoryPath: String) throws {
        guard directoryPath.hasPrefix("/") else { throw DebugScenarioError(description: "output path must be absolute") }
        directory = URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DebugScenarioError(description: "output path is not a plain directory")
        }
        log = directory.appendingPathComponent("frames.jsonl")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
    }

    func write(_ data: Data?, named name: String) {
        // Names come from validated capture names; never let one leave the directory.
        guard let data, !name.contains("/"), !name.hasPrefix(".") else { return }
        do {
            try data.write(to: directory.appendingPathComponent(name, isDirectory: false), options: [.atomic])
        } catch {
            AppLog.interface.error("debug capture not written: \(String(describing: error), privacy: .public)")
        }
    }

    func appendLine(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        do {
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            AppLog.interface.error("debug log not written: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
