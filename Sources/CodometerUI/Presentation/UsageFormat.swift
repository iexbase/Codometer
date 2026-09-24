import CodometerCore
import CodometerL10n
import Foundation

/// Text about usage, resets, sessions and issues, built from domain values in the language of `l10n`.
///
/// The words live in `CodometerL10n` (areas `Usage`, `Window`, `Issues`); this type decides which phrase fits a
/// domain value. Every function that produces text takes the `Localizer` last.
public enum UsageFormat {
    nonisolated public static func providerName(_ provider: ProviderKind) -> String {
        WidgetText.providerName(provider)
    }

    /// Whole percent drawn as a number: "64%", "<1%" for tiny non-zero values so a used window never reads as untouched.
    nonisolated public static func percent(_ value: Percentage, l10n: Localizer) -> String {
        l10n.format.percentCompact(value.value)
    }

    /// "64% used · 36% left".
    nonisolated public static func usedAndLeft(_ value: Percentage, l10n: Localizer) -> String {
        let left = Double(max(0, 100 - Int(value.value.rounded())))
        return l10n.usage.usedAndLeft(used: l10n.format.percentCompact(value.value), left: l10n.format.percentCompact(left))
    }

    /// The window's title in the provider's meaning: "Session · 5h", "Weekly · All models", "Weekly · Sonnet",
    /// the provider's own label for windows without a semantic mapping, else the window's length.
    nonisolated public static func windowTitle(_ window: LimitWindow, l10n: Localizer) -> String {
        WidgetText.windowTitle(window, l10n: l10n)
    }

    /// "Sonnet only" → "Sonnet": the model scope already says the window is limited to that model.
    nonisolated static func modelName(_ model: String) -> String {
        WidgetText.modelName(model)
    }

    /// "Resets in 2h 14m" or "Resets tomorrow at 9:00 AM"; "Resetting…" once the time has passed; `nil` without a
    /// reset time.
    nonisolated public static func resetText(for window: LimitWindow, now: Date, style: ResetTextStyle, l10n: Localizer) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return l10n.usage.resetting }
        switch style {
        case .countdown:
            return l10n.usage.resetsIn(compactDuration(remaining, l10n: l10n))
        case .clockTime:
            return l10n.usage.resets(at: clockText(resetsAt, now: now, l10n: l10n))
        }
    }

    /// "3d 4h", "2h 14m", "42m", "<1m".
    nonisolated public static func compactDuration(_ seconds: TimeInterval, l10n: Localizer) -> String {
        l10n.format.durationCompact(seconds)
    }

    /// "at 6:40 PM", "tomorrow at 9:00 AM", "Fri 12:10 PM", "Sep 19 at 12:10 PM".
    nonisolated public static func clockText(_ date: Date, now: Date, l10n: Localizer) -> String {
        l10n.format.moment(date, now: now)
    }

    public struct PaceText: Equatable, Sendable {
        public let text: String
        public let isWarning: Bool
    }

    nonisolated public static func pace(_ pace: UsagePace, now: Date, l10n: Localizer) -> PaceText {
        switch pace.verdict {
        case .ahead(let points):
            if let exhaustion = pace.projectedExhaustion {
                return PaceText(text: l10n.usage.runsOut(at: clockText(exhaustion, now: now, l10n: l10n)), isWarning: true)
            }
            return PaceText(text: l10n.usage.aheadOfPace(l10n.format.percent(points)), isWarning: true)
        case .behind(let points):
            return PaceText(text: l10n.usage.spare(l10n.format.percent(points)), isWarning: false)
        case .onTrack:
            return PaceText(text: l10n.usage.onPace, isWarning: false)
        }
    }

    nonisolated public static func activity(_ activity: AgentActivity, detail: String?, l10n: Localizer) -> String {
        switch activity {
        case .working:
            return l10n.usage.working
        case .idle:
            return l10n.usage.ready
        case .waiting:
            if isPermissionPrompt(detail) { return l10n.usage.needsApproval }
            return detail?.lowercased() == "input needed" ? l10n.usage.needsInput : l10n.usage.waitingForYou
        }
    }

    /// How long a Codex permission prompt reads as a plain "Needs approval". Codex logs no approval event, so a
    /// command the user already approved keeps looking like a prompt until its output arrives; after this long the
    /// wording hedges.
    nonisolated public static let codexPromptHedgeDelay: TimeInterval = 60

    /// Like `activity(_:detail:l10n:)` for a session of `provider`, except that a Codex permission prompt waiting for
    /// `codexPromptHedgeDelay` or longer reads "Needs approval or running a command". Wording only: the session
    /// still counts as waiting everywhere else (attention queue, notifications).
    nonisolated public static func activity(of session: AgentSession, provider: ProviderKind, now: Date, l10n: Localizer) -> String {
        if provider == .codex,
           session.activity == .waiting,
           isPermissionPrompt(session.detail),
           now.timeIntervalSince(session.activitySince) >= codexPromptHedgeDelay {
            return l10n.usage.approvalOrRunning
        }
        return activity(session.activity, detail: session.detail, l10n: l10n)
    }

    nonisolated static func isPermissionPrompt(_ detail: String?) -> Bool {
        switch detail?.lowercased() {
        case "permission prompt", "permission": true
        default: false
        }
    }

    /// The widest text `railCountdown` produces ("2:14" at most, "47m", "3d"), for reserving a fixed label width in
    /// both languages.
    nonisolated public static let railCountdownTemplate = "00:00"

    /// A countdown short enough for a rail label: "47m" under an hour, "2:14" under a day, "3d" beyond.
    /// Minutes round up, so a countdown never reads "0m" while time remains.
    nonisolated public static func railCountdown(_ seconds: TimeInterval, l10n: Localizer) -> String {
        l10n.format.railCountdown(seconds)
    }

    /// "4m 12s turn · first token in 2.8s", with "interrupted" for an interrupted turn.
    nonisolated public static func turn(_ timing: TurnTiming, l10n: Localizer) -> String {
        var parts = [l10n.usage.turn(l10n.format.durationPrecise(timing.duration))]
        if let latency = timing.firstTokenLatency {
            parts.append(l10n.usage.firstToken(l10n.format.latency(latency)))
        }
        if timing.wasAborted {
            parts.append(l10n.usage.interrupted)
        }
        return parts.joined(separator: " · ")
    }

    /// Hedged wording for an unusual session; `nil` while it looks normal.
    nonisolated public static func health(_ health: SessionHealth, now: Date, l10n: Localizer) -> String? {
        switch health {
        case .normal:
            return nil
        case .quiet(let since):
            return l10n.usage.quiet(for: l10n.format.durationShort(max(60, now.timeIntervalSince(since))))
        case .longTurn:
            return l10n.usage.unusuallyLongTurn
        case .waitingLong:
            return l10n.usage.waitingOver(l10n.format.durationShort(SessionHealth.waitingLongAfter))
        }
    }

    /// Like `health(_:now:l10n:)`, but a long wait reads with its real length: "Waiting 12 min".
    nonisolated public static func health(of session: AgentSession, now: Date, l10n: Localizer) -> String? {
        let verdict = session.health(now: now)
        if case .waitingLong = verdict {
            return l10n.usage.waiting(for: l10n.format.durationShort(max(60, now.timeIntervalSince(session.activitySince))))
        }
        return health(verdict, now: now, l10n: l10n)
    }

    /// A session named by its project folder and the end of its id: "Codometer · 3f9a1c", or "Session 3f9a1c" without a
    /// project. `includesID: false` drops the id when there is a folder ("Codometer"), where the id is noise.
    nonisolated public static func sessionLabel(_ parts: SessionLabelParts, includesID: Bool = true, l10n: Localizer) -> String {
        guard let folder = parts.folder else { return l10n.usage.unnamedSession(parts.idSuffix) }
        return includesID ? parts.machineForm : folder
    }

    /// The e-mail as the user wants it shown: as is, masked (`e••••e@test.com`) or not at all.
    nonisolated public static func email(_ address: String?, visibility: EmailVisibility) -> String? {
        guard let address, !address.isEmpty else { return nil }
        switch visibility {
        case .visible: return address
        case .masked: return DisplayText.maskEmail(address)
        case .hidden: return nil
        }
    }

    nonisolated public static func email(_ identity: AccountIdentity?, visibility: EmailVisibility) -> String? {
        email(identity?.email, visibility: visibility)
    }

    /// The organisation name with any e-mail inside it masked or removed per `visibility`.
    ///
    /// Personal Claude organisations are named after the address ("me@example.com's Organization"), so the name
    /// would leak what the e-mail setting hides. When hidden, such a name is dropped entirely.
    nonisolated public static func organization(_ identity: AccountIdentity?, visibility: EmailVisibility) -> String? {
        guard let organization = identity?.organization, !organization.isEmpty else { return nil }
        guard visibility != .visible, organization.contains("@") else { return organization }
        guard visibility == .masked else { return nil }
        return organization
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard word.contains("@") else { return String(word) }
                let possessive = word.firstIndex { $0 == "'" || $0 == "’" }
                let address = possessive.map { word[..<$0] } ?? word[...]
                let suffix = possessive.map { word[$0...] } ?? ""
                return DisplayText.maskEmail(String(address)) + suffix
            }
            .joined(separator: " ")
    }

    /// "Next refresh in 3 min"; "Refreshing soon" once the time has come.
    nonisolated public static func nextRefresh(_ date: Date, now: Date, l10n: Localizer) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return l10n.usage.nextRefreshNow }
        return l10n.usage.nextRefresh(in: l10n.format.durationShort(remaining))
    }

    /// Estimated percentage points of a window: "≈3.2%", "≈12%", "<0.1%".
    nonisolated public static func attributionPoints(_ points: Double, l10n: Localizer) -> String {
        l10n.format.approxPercent(points)
    }

    nonisolated public static func elapsed(since date: Date, now: Date, l10n: Localizer) -> String {
        compactDuration(max(0, now.timeIntervalSince(date)), l10n: l10n)
    }

    /// "just now", "2 min ago".
    nonisolated public static func age(since date: Date, now: Date, l10n: Localizer) -> String {
        l10n.format.ago(date, now: now)
    }

    nonisolated public static func issue(_ issue: TrackerIssue, provider: ProviderKind, l10n: Localizer) -> String {
        let name = providerName(provider)
        let issues = l10n.issues
        switch issue.kind {
        case .executableMissing:
            return provider == .claude ? issues.claudeCodeMissing : issues.codexMissing
        case .executableUntrusted:
            return issues.untrusted(name)
        case .signedOut:
            return issues.signedOut(name)
        case .unexpectedOutput:
            return issues.unexpectedOutput(name)
        case .commandFailed:
            return issues.commandFailed(name)
        case .timedOut:
            return issues.timedOut(name)
        case .profileMissing:
            return issues.profileMissing
        case .offline:
            return issues.offline
        case .internalFailure:
            return issues.internalFailure
        }
    }

    nonisolated public static func credits(_ credits: CreditsInfo, l10n: Localizer) -> String? {
        if credits.isUnlimited { return l10n.usage.creditsUnlimited }
        guard credits.hasCredits, let balance = credits.balance else { return nil }
        return l10n.usage.credits(NSDecimalNumber(decimal: balance).description(withLocale: l10n.locale))
    }
}
