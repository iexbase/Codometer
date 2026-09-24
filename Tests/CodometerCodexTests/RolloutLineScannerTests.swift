@testable import CodometerCodex
import Foundation
import Testing

private func scanAll(_ line: String) -> RolloutLineFields {
    RolloutLineScanner.scan(Data(line.utf8)) { _ in false }
}

private func callID(_ line: String) -> String? {
    RolloutValue.identifier(scanAll(line).callID?.string)
}

private func escalates(_ text: String) -> Bool {
    Data(text.utf8).withUnsafeBytes { RolloutLineScanner.requestsEscalation($0) }
}

@Suite("Rollout line scanner")
struct RolloutLineScannerTests {
    @Test("Envelope and payload fields are read by position")
    func positions() {
        let fields = scanAll(Rollout.escalatedExec(at: "2026-09-16T18:55:10.000Z", callID: "call_Ab-9"))
        #expect(fields.timestamp == .string("2026-09-16T18:55:10.000Z"))
        #expect(fields.type == .string("response_item"))
        #expect(fields.payloadType == .string("custom_tool_call"))
        #expect(fields.callID == .string("call_Ab-9"))
        #expect(fields.name == .string("exec"))
    }

    @Test("Scanning stops as soon as the caller has what it needs")
    func stopsEarly() {
        // Everything after the payload type is garbage; an early stop never reaches it.
        let line = #"{"timestamp":"t","type":"response_item","payload":{"type":"message","call_id":"late"#
        let fields = RolloutLineScanner.scan(Data(line.utf8)) { $0.payloadType != nil }
        #expect(fields.payloadType == .string("message"))
        #expect(fields.callID == nil)
    }

    @Test("Whitespace around the colon is allowed")
    func whitespace() {
        #expect(callID(#"{"type" : "response_item", "payload" : { "type" : "function_call_output" , "call_id" :  "call_1" }}"#) == "call_1")
    }

    @Test("call_id text inside strings or nested objects is never taken for the field")
    func ignoresLookalikes() {
        let inInput = #"{"type":"response_item","payload":{"type":"custom_tool_call","input":"{\"call_id\":\"fake\"}","call_id":"real_1"}}"#
        #expect(callID(inInput) == "real_1")
        let nested = #"{"type":"response_item","payload":{"type":"function_call_output","output":{"call_id":"deep"},"call_id":"real_2"}}"#
        #expect(callID(nested) == "real_2")
        let envelopeMetadata = #"{"type":"response_item","metadata":{"call_id":"meta"},"payload":{"type":"function_call_output","call_id":"real_3"}}"#
        #expect(callID(envelopeMetadata) == "real_3")
        let arrayPayload = #"{"type":"response_item","payload":[{"call_id":"in_array"}]}"#
        #expect(callID(arrayPayload) == nil)
    }

    @Test("Escaped quotes and backslash runs close strings correctly")
    func escapes() {
        let evenBackslashes = #"{"type":"response_item","payload":{"type":"custom_tool_call","input":"C:\\","call_id":"after_backslash"}}"#
        #expect(callID(evenBackslashes) == "after_backslash")
        let escapedQuote = #"{"type":"response_item","payload":{"type":"custom_tool_call","input":"say \"hi\\\" \\\\\"","call_id":"after_quotes"}}"#
        #expect(callID(escapedQuote) == "after_quotes")
        let escapedValue = #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"call_\"x"}}"#
        #expect(scanAll(escapedValue).callID == .unusable)
        #expect(callID(escapedValue) == nil)
    }

    @Test("call_id validation: charset, empty, length, non-string")
    func validation() {
        func line(_ value: String) -> String {
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":\#(value)}}"#
        }
        #expect(callID(line(#""call_abc-DEF_123""#)) == "call_abc-DEF_123")
        #expect(callID(line(#""""#)) == nil)
        #expect(callID(line(#""a.b""#)) == nil)
        #expect(callID(line(#""a b""#)) == nil)
        #expect(callID(line(#""звонок""#)) == nil)
        #expect(callID(line("42")) == nil)
        #expect(callID(line("null")) == nil)
        let longest = String(repeating: "a", count: 128)
        #expect(callID(line("\"\(longest)\"")) == longest)
        #expect(callID(line("\"\(longest)a\"")) == nil)
    }

    @Test("Numbers, literals and containers are told apart")
    func scalars() {
        let line = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":null,"duration_ms":-12,"time_to_first_token_ms":2800,"reason":{"x":1},"model":true}}"#
        let fields = scanAll(line)
        #expect(fields.turnID?.isNull == true)
        #expect(fields.durationMs?.int64 == -12)
        #expect(fields.firstTokenMs?.int64 == 2_800)
        #expect(fields.reason == .container)
        #expect(fields.model == .literal("true"))
    }

    @Test("Malformed and truncated lines never crash")
    func malformed() {
        #expect(scanAll("") == RolloutLineFields())
        #expect(scanAll("{") == RolloutLineFields())
        #expect(scanAll(#"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"unterminated"#).callID == .unusable)
        #expect(scanAll(#"}}}]]"type":"x"{{"#).type == nil)
        #expect(scanAll(#"{"type":"#).type == nil)
        #expect(scanAll(#"{"payload":{"type":"a"}}"#).payloadType == .string("a"))
    }

    @Test("Escalation needs the sandbox_permissions key right before the value")
    func escalation() {
        #expect(escalates(#"{\"sandbox_permissions\":\"require_escalated\"}"#))
        #expect(escalates(#"sandbox_permissions: \"require_escalated\""#))
        #expect(escalates(#"sandbox_permissions="require_escalated""#))
        #expect(escalates(#"sandbox_permissions: ['require_escalated']"#))
        #expect(!escalates("require_escalated"))
        #expect(!escalates("grep -rn require_escalated Sources"))
        #expect(!escalates("sandbox_permissionsrequire_escalated"))
        #expect(!escalates("sandbox_permissions: \"\"\"\"\"\"\"\"\"require_escalated"))
        #expect(!escalates("sandbox_permissions is not require_escalated"))
        #expect(escalates("require_escalated then sandbox_permissions:\"require_escalated\""))
        #expect(!escalates(""))
    }
}
