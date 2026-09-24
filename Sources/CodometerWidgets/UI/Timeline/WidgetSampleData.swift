import CodometerCore
import CodometerL10n
import Foundation

/// Plausible content for the widget gallery and the placeholder while the real snapshot loads.
/// Contains no real account data.
public enum WidgetSampleData {
    /// Window titles are written in `language`, which the snapshot also carries; `layout` is the user's choice when
    /// a snapshot says it, so the gallery previews the look they picked.
    public static func snapshot(now: Date, language: Language, layout: WidgetLayout = .rings) -> WidgetSnapshot {
        let claude = account(
            id: "6F1D2A4E-3C1B-4B7A-9E51-0A6D1C2B3E01",
            label: "Claude",
            provider: .claude,
            tint: .teal,
            monogram: "1",
            plan: "Max",
            capturedAt: now.addingTimeInterval(-120),
            windows: [
                window(bucket: "claude", id: "session", scope: .session, used: 42, minutes: 300, resetsIn: 2 * 3_600 + 14 * 60, now: now, language: language),
                window(bucket: "claude", id: "week", scope: .weekly(model: nil), used: 38, minutes: 10_080, resetsIn: 3 * 86_400, now: now, language: language),
                window(bucket: "claude", id: "week.fable", scope: .weekly(model: "Fable"), used: 63, minutes: 10_080, resetsIn: 3 * 86_400, now: now, language: language),
            ]
        )
        let codex = account(
            id: "6F1D2A4E-3C1B-4B7A-9E51-0A6D1C2B3E02",
            label: "Codex",
            provider: .codex,
            tint: .indigo,
            monogram: "1",
            plan: "Pro",
            capturedAt: now.addingTimeInterval(-60),
            windows: [
                window(bucket: "codex", id: "primary", scope: .rolling, used: 18, minutes: 300, resetsIn: 3 * 3_600 + 5 * 60, now: now, language: language),
                window(bucket: "codex", id: "secondary", scope: .rolling, used: 27, minutes: 10_080, resetsIn: 5 * 86_400, now: now, language: language),
            ]
        )
        return WidgetSnapshot(
            generatedAt: now,
            accounts: [claude, codex].compactMap { $0 },
            bands: .standard,
            attentionCount: 0,
            workingCount: 1,
            language: language,
            layout: layout
        )
    }

    private static func account(
        id: String,
        label: String,
        provider: ProviderKind,
        tint: AccountTint,
        monogram: String,
        plan: String,
        capturedAt: Date,
        windows: [WidgetWindow?]
    ) -> WidgetAccount? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let kept = windows.compactMap { $0 }
        return try? WidgetAccount(
            id: AccountID(rawValue: uuid),
            label: label,
            provider: provider,
            tint: tint,
            // The label is only the provider's name, so the automatic monogram is the account's ordinal.
            monogram: try? AccountMonogram(validating: monogram),
            plan: plan,
            windows: kept,
            primaryWindowID: kept.first?.id,
            capturedAt: capturedAt
        )
    }

    private static func window(
        bucket: String,
        id: String,
        scope: LimitWindowScope,
        used: Double,
        minutes: Int,
        resetsIn seconds: TimeInterval,
        now: Date,
        language: Language
    ) -> WidgetWindow? {
        do throws(ValidationError) {
            let limit = try LimitWindow(
                id: id,
                scope: scope,
                used: try Percentage(validating: used),
                duration: try WindowDuration(minutes: minutes),
                resetsAt: now.addingTimeInterval(seconds)
            )
            return try WidgetWindow(bucketID: bucket, isMainBucket: true, window: limit, language: language)
        } catch {
            return nil
        }
    }
}
