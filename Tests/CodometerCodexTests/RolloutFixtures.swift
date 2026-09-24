@testable import CodometerCodex
import CodometerCore
import Foundation
import Testing

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Synthetic rollout lines in the shapes codex-cli 0.154 writes. Key order follows the real logs; every
/// text field holds made-up filler, never real conversation content.
enum Rollout {
    static let sessionID = "01a0ab92-37ce-7552-b4ad-ada1b6ba2f4c"
    static let project = "/Users/dev/weather-app"
    static let model = "gpt-5.3-codex"

    static func date(_ text: String) -> Date {
        CodexRolloutParser.parseTimestamp(text) ?? .distantPast
    }

    static func sessionMeta(
        at time: String,
        originator: String = "codex-tui",
        cliVersion: String = "0.154.0",
        threadID: String = sessionID
    ) -> String {
        #"{"timestamp":"\#(time)","ordinal":0,"type":"session_meta","payload":{"session_id":"\#(sessionID)","id":"\#(threadID)","timestamp":"\#(time)","cwd":"\#(project)","originator":"\#(originator)","cli_version":"\#(cliVersion)","source":"cli","thread_source":"user","model_provider":"openai","base_instructions":{"text":"You are a coding agent. \"cwd\":\"/elsewhere\" is only text."},"history_mode":"full","git":{"branch":"main"}}}"#
    }

    static func turnContext(
        at time: String,
        turnID: String = "turn-1",
        policy: String = #""on-request""#,
        reviewer: String? = "user",
        model: String = model,
        effort: String = "high"
    ) -> String {
        let reviewerField = reviewer.map { #""approvals_reviewer":"\#($0)","# } ?? ""
        return #"{"timestamp":"\#(time)","ordinal":3,"type":"turn_context","payload":{"turn_id":"\#(turnID)","root_turn_id":"\#(turnID)","cwd":"\#(project)","workspace_roots":["\#(project)"],"current_date":"2026-09-16","timezone":"Europe/Moscow","approval_policy":\#(policy),\#(reviewerField)"sandbox_policy":{"type":"workspace-write","network_access":false},"permission_profile":{"type":"managed"},"model":"\#(model)","comp_hash":"abc","personality":"pragmatic","collaboration_mode":{"mode":"default","settings":{"developer_instructions":"Filler instructions mentioning \"model\":\"other\".","model":"other-model","reasoning_effort":"low"}},"multi_agent_version":"v2","realtime_active":false,"effort":"\#(effort)","summary":"auto"}}"#
    }

    static func taskStarted(at time: String, turnID: String = "turn-1") -> String {
        #"{"timestamp":"\#(time)","ordinal":4,"type":"event_msg","payload":{"type":"task_started","turn_id":"\#(turnID)","started_at":1789584900,"model_context_window":272000,"collaboration_mode_kind":"default"}}"#
    }

    static func taskComplete(at time: String, turnID: String = "turn-1", durationMs: String = "252000", firstTokenMs: String = "2800") -> String {
        #"{"timestamp":"\#(time)","ordinal":40,"type":"event_msg","payload":{"type":"task_complete","turn_id":"\#(turnID)","last_agent_message":"Done. Filler reply with \"duration_ms\":1 inside.","started_at":1789584900,"completed_at":1789585152,"duration_ms":\#(durationMs),"time_to_first_token_ms":\#(firstTokenMs)}}"#
    }

    static func turnAborted(at time: String, turnID: String = "turn-1", durationMs: String = "5000", reason: String = "interrupted") -> String {
        #"{"timestamp":"\#(time)","ordinal":41,"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"\#(turnID)","reason":"\#(reason)","started_at":1789584900,"completed_at":1789584905,"duration_ms":\#(durationMs)}}"#
    }

    static func tokenUsageRecord(
        at time: String,
        responseID: String,
        input: Int = 1_200,
        cached: Int = 1_000,
        output: Int = 300,
        reasoning: Int = 120
    ) -> String {
        let usage = #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(input + output)}"#
        return #"{"timestamp":"\#(time)","ordinal":20,"type":"token_usage_record","payload":{"session_id":"\#(sessionID)","thread_id":"\#(sessionID)","turn_id":"turn-1","root_turn_id":"turn-1","response_id":"\#(responseID)","usage":\#(usage),"turn_token_usage":\#(usage),"thread_token_usage":\#(usage)}}"#
    }

    static func tokenCount(at time: String, input: Int = 900, cached: Int = 400, output: Int = 80, total: Int = 5_000) -> String {
        #"{"timestamp":"\#(time)","ordinal":21,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":10,"total_tokens":\#(input + output)},"model_context_window":272000},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":1789600000},"secondary":null,"credits":null,"individual_limit":null,"spend_control_reached":null,"plan_type":"pro","rate_limit_reached_type":null}}}"#
    }

    /// The `exec` custom tool with a JavaScript-like input asking to leave the sandbox.
    static func escalatedExec(at time: String, callID: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":10,"type":"response_item","payload":{"type":"custom_tool_call","id":"ctc_1","status":"completed","call_id":"\#(callID)","name":"exec","input":"await tools.exec_command({cmd: \"swift build\", sandbox_permissions: \"require_escalated\", justification: \"filler\"})","internal_chat_message_metadata_passthrough":{"create_time":1789584910.5,"turn_id":"turn-1"}}}"#
    }

    /// A `function_call` whose JSON arguments ask to leave the sandbox.
    static func escalatedFunctionCall(at time: String, callID: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":10,"type":"response_item","payload":{"type":"function_call","id":"fc_1","name":"shell","arguments":"{\"command\":[\"swift\",\"test\"],\"sandbox_permissions\":\"require_escalated\",\"justification\":\"filler\"}","call_id":"\#(callID)","internal_chat_message_metadata_passthrough":{"create_time":1789584910.5,"turn_id":"turn-1"}}}"#
    }

    /// An ordinary `exec` call whose input only mentions the escalation keyword.
    static func execMentioningEscalation(at time: String, callID: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":10,"type":"response_item","payload":{"type":"custom_tool_call","id":"ctc_2","status":"completed","call_id":"\#(callID)","name":"exec","input":"await tools.exec_command({cmd: \"grep -rn require_escalated Sources\"})","internal_chat_message_metadata_passthrough":{"create_time":1789584910.5,"turn_id":"turn-1"}}}"#
    }

    static func requestUserInput(at time: String, callID: String, name: String = "request_user_input") -> String {
        #"{"timestamp":"\#(time)","ordinal":11,"type":"response_item","payload":{"type":"function_call","id":"fc_2","name":"\#(name)","arguments":"{\"questions\":[{\"question\":\"Filler question?\"}]}","call_id":"\#(callID)","internal_chat_message_metadata_passthrough":{"create_time":1789584911.0,"turn_id":"turn-1"}}}"#
    }

    static func customToolCallOutput(at time: String, callID: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":12,"type":"response_item","payload":{"type":"custom_tool_call_output","id":"out_1","call_id":"\#(callID)","output":[{"type":"input_text","text":"Filler output \"call_id\":\"other\""}],"internal_chat_message_metadata_passthrough":{"create_time":1789584920.0,"turn_id":"turn-1"}}}"#
    }

    static func functionCallOutput(at time: String, callID: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":12,"type":"response_item","payload":{"type":"function_call_output","id":"out_2","call_id":"\#(callID)","output":"Filler output"},"metadata":{"call_id":"metadata-id","type":"x"}}"#
    }

    static func message(at time: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":5,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Filler prompt: {\"type\":\"function_call\",\"call_id\":\"fake\",\"sandbox_permissions\":\"require_escalated\"} token_count task_complete"}]}}"#
    }

    /// An assistant message padded to about `bytes` bytes, standing in for long tool output and replies.
    static func filler(at time: String, bytes: Int) -> String {
        #"{"timestamp":"\#(time)","ordinal":7,"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"\#(String(repeating: "lorem ipsum ", count: max(1, bytes / 12)))"}]}}"#
    }

    static func compacted(at time: String) -> String {
        #"{"timestamp":"\#(time)","ordinal":6,"type":"compacted","payload":{"message":"Summary: called custom_tool_call with sandbox_permissions require_escalated earlier."}}"#
    }
}

/// A throwaway Codex profile with one rollout file.
struct RolloutProfile {
    let directory: TemporaryDirectory
    let layout: CodexProfileLayout
    let file: URL
    let accountID = AccountID()

    init() throws {
        directory = try TemporaryDirectory()
        let home = directory.url.appendingPathComponent(".codex-test", isDirectory: true)
        let day = home.appendingPathComponent("sessions/2026/09/16", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        file = day.appendingPathComponent("rollout-2026-09-16T22-54-41-\(Rollout.sessionID).jsonl")
        layout = CodexProfileLayout(home: home, homeDirectory: directory.url)
    }

    func reader() -> CodexSessionLogReader {
        CodexSessionLogReader(layout: layout, accountID: accountID)
    }

    func sibling(named name: String) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(name)
    }

    func write(_ lines: [String], to url: URL? = nil) throws {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url ?? file)
    }

    func append(_ lines: [String], to url: URL? = nil) throws {
        let handle = try FileHandle(forWritingTo: url ?? file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

func events(_ line: String, scanningCallOutputs: Bool = false) -> [CodexRolloutEvent] {
    CodexRolloutParser.events(in: Data(line.utf8), scanningCallOutputs: scanningCallOutputs)
}
