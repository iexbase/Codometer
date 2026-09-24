import CodometerL10n
import Foundation

/// The texts the desktop widget shows, in the snapshot's language.
///
/// Core cannot use the UI module's `UsageFormat`, so the few texts the snapshot and the widget need live here, and
/// `UsageFormat.windowTitle` delegates to `windowTitle(_:l10n:)`. Window titles follow the provider's meaning:
/// "Session · 5h", "Weekly · All models", "Weekly · Sonnet", the provider's own label, else the window's length.
public enum WidgetText {
    public static func providerName(_ provider: ProviderKind) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public static func windowTitle(_ window: LimitWindow, l10n: Localizer) -> String {
        switch window.scope {
        case .session:
            return l10n.window.session(length: durationTitle(minutes: window.duration?.minutes ?? WindowDuration.fiveHours.minutes, l10n: l10n))
        case .weekly(let model?):
            return l10n.window.weekly(model: modelName(model))
        case .weekly(nil):
            return l10n.window.weeklyAllModels
        case .rolling:
            if let label = window.label { return label }
            guard let minutes = window.duration?.minutes else {
                return window.id == "primary" ? l10n.window.mainLimit : l10n.window.extraLimit
            }
            return durationTitle(minutes: minutes, l10n: l10n)
        }
    }

    /// "Sonnet only" → "Sonnet": the model scope already says the window is limited to that model.
    public static func modelName(_ model: String) -> String {
        let suffix = " only"
        guard model.count > suffix.count, model.lowercased().hasSuffix(suffix) else { return model }
        return String(model.dropLast(suffix.count))
    }

    /// A window length as a title: the named lengths ("Weekly", "Daily", "Monthly"), else `5h`, `45m`, `3d`.
    static func durationTitle(minutes: Int, l10n: Localizer) -> String {
        switch minutes {
        case 10_080: l10n.window.weekly
        case 1_440: l10n.window.daily
        case 43_200, 43_800, 44_640: l10n.window.monthly
        default: l10n.window.length(minutes: minutes)
        }
    }

    /// A window's length in a few characters, for the caption inside a small ring: `5h`, `wk`, `day`, `mo`, `45m`,
    /// `3d`; `nil` when the length is unknown.
    public static func shortDuration(_ window: LimitWindow, l10n: Localizer) -> String? {
        window.duration.map { l10n.widgetFormat.ringCaption(minutes: $0.minutes) }
    }

    /// An account label inside its provider's own widget, where the provider is already named: "Codex · Work" →
    /// "Work". Labels that are only the provider's name, or do not start with it, stay as they are.
    public static func labelWithinProvider(_ label: String, provider: ProviderKind) -> String {
        let name = providerName(provider)
        guard label.count > name.count, label.lowercased().hasPrefix(name.lowercased()) else { return label }
        let rest = label.dropFirst(name.count)
        guard let first = rest.first, first == " " || first == "·" || first == "-" || first == "—" || first == ":" else {
            return label
        }
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "·-—:"))
        let trimmed = String(rest).trimmingCharacters(in: separators)
        return trimmed.isEmpty ? label : trimmed
    }

    /// A compact name for a model bucket: "GPT-5.3-Codex-Spark" → "Spark". The last hyphen-separated part names
    /// the variant; titles without one, or whose last part is a bare version, stay as they are.
    public static func shortBucketTitle(_ title: String) -> String {
        let parts = title.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count > 1, let last = parts.last, last.count >= 2, last.contains(where: \.isLetter) else {
            return title
        }
        return last
    }

    /// Whole percent without the sign, "<1" for tiny non-zero values: the widget sets the sign in a smaller size.
    public static func percentNumber(_ value: Percentage) -> String {
        if value.value > 0 && value.value < 1 { return "<1" }
        return "\(Int(value.value.rounded()))"
    }

    /// "63%", "<1%".
    public static func percent(_ value: Percentage) -> String {
        percentNumber(value) + "%"
    }

    /// The e-mail as the user wants it shown: as is, masked or not at all.
    public static func email(_ address: String?, visibility: EmailVisibility) -> String? {
        guard let address, !address.isEmpty else { return nil }
        switch visibility {
        case .visible: return address
        case .masked: return DisplayText.maskEmail(address)
        case .hidden: return nil
        }
    }

    /// A short reason an account has no fresh numbers.
    public static func notice(for issue: TrackerIssue.Kind, l10n: Localizer) -> String {
        let text = l10n.widgetFormat
        return switch issue {
        case .executableMissing: text.cliMissing
        case .executableUntrusted: text.cliUntrusted
        case .signedOut: text.signedOut
        case .unexpectedOutput: text.unfamiliarData
        case .commandFailed, .internalFailure: text.refreshFailed
        case .timedOut: text.notResponding
        case .profileMissing: text.profileFolderMissing
        case .offline: text.offline
        }
    }
}
