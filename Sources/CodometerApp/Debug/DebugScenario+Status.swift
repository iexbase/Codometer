#if DEBUG
import CodometerCore
import CodometerUI
import Foundation

/// Service status steps.
///
/// `{"serviceStatus": {"provider": "claude", "level": "partialOutage", "components": ["Claude Code"]}}` puts one
/// vendor's status on the board in memory, with no network access at all; several steps build up a board with both
/// vendors. `{"serviceStatus": null}` clears the board and lets real checks resume.
extension DebugScenario {
    static func handleStatusStep(_ key: String, _ value: Any, _ context: DebugContext) async throws -> Bool {
        guard key == "serviceStatus" else { return false }
        func fail(_ reason: String) -> DebugScenarioError {
            DebugScenarioError(description: "serviceStatus: \(reason)")
        }
        if DebugValue.isNull(value) {
            context.controller.setDebugServiceStatus(nil)
            context.log(["action": "serviceStatus", "cleared": true])
            return true
        }
        guard let object = DebugValue.object(value), Set(object.keys).isSubset(of: ["provider", "level", "components"]) else {
            throw fail("expected null or {provider, level, components}")
        }
        guard let rawProvider = object["provider"].flatMap(DebugValue.string), let provider = ProviderKind(rawValue: rawProvider) else {
            throw fail("provider must be one of \(ProviderKind.allCases.map(\.rawValue))")
        }
        var level: ServiceStatusLevel?
        if let rawLevel = object["level"], !DebugValue.isNull(rawLevel) {
            guard let name = DebugValue.string(rawLevel), let parsed = ServiceStatusLevel(rawValue: name) else {
                throw fail("level must be null or one of \(ServiceStatusLevel.allCases.map(\.rawValue))")
            }
            level = parsed
        }
        var components: [String] = []
        if let raw = object["components"] {
            guard let list = raw as? [Any] else { throw fail("components must be an array of strings") }
            components = try list.map { item in
                guard let name = DebugValue.string(item) else { throw fail("components must be an array of strings") }
                return name
            }
        }
        var board = context.store.serviceStatus
        board.statuses[provider] = ServiceStatus(
            provider: provider,
            level: level,
            affectedComponents: components,
            checkedAt: context.store.now
        )
        context.controller.setDebugServiceStatus(board)
        context.log(["action": "serviceStatus", "provider": provider.rawValue, "level": level?.rawValue ?? "none"])
        return true
    }

    /// Fields this domain adds to `capture` and `trace` lines.
    static func statusTraceFields(_ context: DebugContext) -> [String: Any] {
        let board = context.store.serviceStatus
        guard !board.statuses.isEmpty else { return [:] }
        let items = ProviderKind.allCases.compactMap { provider -> String? in
            guard let status = board.statuses[provider] else { return nil }
            return "\(provider.rawValue):\(status.level?.rawValue ?? "ok")"
        }
        return ["serviceStatus": items.joined(separator: ",")]
    }
}
#endif
