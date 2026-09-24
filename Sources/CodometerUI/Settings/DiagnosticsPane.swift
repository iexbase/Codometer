import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// Settings → Diagnostics: the system check, how each account's refreshes are going, the provider tools, the data
/// format, storage and crash reports.
///
/// Everything here is pulled, never pushed: the engine is asked once when the pane appears and every five seconds
/// while the Settings window is on screen. Leaving the pane cancels the loop, so a closed pane costs nothing.
struct DiagnosticsPane: View {
    let store: TrackerStore

    @State private var diagnostics: EngineDiagnostics?
    @State private var report: SystemCheckReport?
    @State private var isChecking = false
    @State private var includeAccountNames = false
    @State private var isWindowOnScreen = false
    @State private var copiedAt: Date?
    @State private var crashReports: [CrashReportSummary] = []
    @Environment(\.l10n) private var l10n

    /// How often the pane asks the engine again while someone can see it.
    static let refreshInterval: Duration = .seconds(5)

    // No `.animation` anywhere in this pane: animating a grouped form's rows costs hundreds of milliseconds of
    // main-thread work (measured with the harness `monitor`), and every slot that changes keeps its size anyway.
    var body: some View {
        Form {
            headerSection
            checkSection
            accountsSection
            toolsSection
            driftSection
            storageSection
            crashSection
        }
        .formStyle(.grouped)
        .background {
            WindowVisibilityReader { isWindowOnScreen = $0 }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        // Once when the pane appears, so an off-screen capture still has data.
        .task {
            crashReports = store.actions.recentCrashReports()
            #if DEBUG
            if report == nil { report = DiagnosticsDebugReport.value }
            #endif
            diagnostics = await store.actions.loadDiagnostics()
        }
        // And then only while the window is visible; leaving the pane cancels this task.
        .task(id: isWindowOnScreen) {
            guard isWindowOnScreen else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval, tolerance: .seconds(1))
                guard !Task.isCancelled else { return }
                diagnostics = await store.actions.loadDiagnostics()
            }
        }
    }

    // MARK: - System check

    private var headerSection: some View {
        Section {
            PaneHeader(
                title: l10n.settingsPanes.diagnostics,
                subtitle: l10n.diagnostics.paneSubtitle,
                systemImage: "stethoscope",
                tint: .mint
            )
        }
    }

    private var checkSection: some View {
        Section {
            HStack(spacing: 10) {
                Button(l10n.diagnostics.checkSystem) { runCheck() }
                    .buttonStyle(.glassProminent)
                    .frame(minHeight: SettingsMetrics.hitTarget)
                    .disabled(isChecking)
                // A fixed slot, so starting a check never moves the row.
                ProgressView()
                    .controlSize(.small)
                    .opacity(isChecking ? 1 : 0)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(!isChecking)
                    .accessibilityLabel(l10n.diagnostics.checking)
                Spacer(minLength: 8)
                Text(lastCheckedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let report {
                ForEach(report.items) { item in
                    CheckItemRow(item: item)
                }
            } else {
                SectionNote(l10n.diagnostics.checkIntro)
            }
            Toggle(isOn: $includeAccountNames) {
                SettingsRowLabel(title: l10n.diagnostics.includeNames, systemImage: "person.text.rectangle", tint: .blue)
            }
            .settingsControl(title: l10n.diagnostics.includeNames)
            HStack(spacing: 10) {
                Spacer()
                // A reserved slot, so confirming a copy never moves the buttons.
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 16, height: 16)
                    .opacity(copiedAt == nil ? 0 : 1)
                    .accessibilityHidden(copiedAt == nil)
                    .accessibilityLabel(l10n.diagnostics.copied)
                Button(l10n.diagnostics.copyReport) { copyReport() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
                    .disabled(report == nil)
                Button(l10n.diagnostics.exportReport) { store.actions.exportDiagnostics(includeAccountNames) }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
                    .disabled(report == nil)
            }
        } header: {
            Text(l10n.diagnostics.checkTitle)
        } footer: {
            SectionNote(l10n.diagnostics.reportFooter)
        }
    }

    private var lastCheckedText: String {
        guard let report else { return l10n.diagnostics.neverChecked }
        return l10n.diagnostics.lastChecked(l10n.format.ago(report.ranAt, now: store.now))
    }

    private func runCheck() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let result = await store.actions.runSystemCheck()
            isChecking = false
            copiedAt = nil
            guard let result else { return }
            report = result
        }
    }

    private func copyReport() {
        guard let report else { return }
        store.actions.copyDiagnosticsReport(report, includeAccountNames)
        copiedAt = store.now
        Task {
            try? await Task.sleep(for: .seconds(2), tolerance: .seconds(1))
            copiedAt = nil
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        Section(l10n.diagnostics.accountsTitle) {
            let byID = Dictionary(
                (diagnostics?.accounts ?? []).map { ($0.accountID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let accounts = store.presentations
            if accounts.isEmpty {
                SectionNote(l10n.diagnostics.noAccounts)
            } else {
                ForEach(accounts) { account in
                    AccountDiagnosticsRow(
                        presentation: account,
                        diagnostics: byID[account.id],
                        now: store.now
                    ) {
                        store.refresh(account.id)
                    }
                }
            }
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        Section(l10n.diagnostics.toolsTitle) {
            ForEach(ProviderKind.allCases, id: \.self) { provider in
                ToolRow(provider: provider, diagnostics: diagnostics?.executables[provider])
            }
        }
    }

    // MARK: - Data format

    @ViewBuilder
    private var driftSection: some View {
        let severity = (diagnostics?.accounts ?? []).map(\.drift.severity).max() ?? FormatDrift.Severity.none
        if severity != .none {
            Section(l10n.diagnostics.driftTitle) {
                Label {
                    Text(severity == .paused ? l10n.diagnostics.driftPaused : l10n.diagnostics.driftNote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: severity == .paused ? "exclamationmark.triangle.fill" : "info.circle")
                        .symbolRenderingMode(severity == .paused ? .multicolor : .monochrome)
                }
                .font(.callout)
                HStack {
                    Spacer()
                    Button(l10n.accounts.refreshNow) { store.refresh(nil) }
                        .buttonStyle(.glass)
                        .frame(minHeight: SettingsMetrics.hitTarget)
                }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section(l10n.diagnostics.storageTitle) {
            let history = diagnostics?.history
            valueRow(
                title: l10n.diagnostics.historySize,
                value: history?.fileBytes.map { DiagnosticsText.fileSize($0, l10n: l10n) } ?? l10n.common.noData,
                systemImage: "internaldrive.fill",
                tint: .gray
            )
            valueRow(
                title: l10n.diagnostics.historyState,
                value: history.map { DiagnosticsText.health($0.health, l10n: l10n) } ?? l10n.common.noData,
                systemImage: "clock.arrow.circlepath",
                tint: .indigo
            )
            valueRow(
                title: l10n.diagnostics.oldestEntry,
                // Weeks back, so it needs its date: `format.moment` would print a bare weekday for it.
                value: history?.oldestSampleAt.map { l10n.diagnostics.pastMoment($0) } ?? l10n.common.noData,
                systemImage: "calendar",
                tint: .teal
            )
            valueRow(
                title: l10n.diagnostics.keptFor,
                value: l10n.diagnostics.days(history?.retentionDays ?? store.settings.general.historyRetention.days),
                systemImage: "tray.full.fill",
                tint: .brown
            )
        }
    }

    // MARK: - Crash reports

    @ViewBuilder
    private var crashSection: some View {
        if !crashReports.isEmpty {
            Section {
                ForEach(crashReports) { crash in
                    valueRow(
                        title: DiagnosticsText.crashKind(crash.kind, l10n: l10n),
                        value: l10n.diagnostics.pastMoment(crash.date),
                        systemImage: "ant.fill",
                        tint: .red
                    )
                }
            } header: {
                Text(l10n.diagnostics.crashTitle)
            } footer: {
                SectionNote(l10n.diagnostics.crashFooter)
            }
        }
    }

    private func valueRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// A check result the debug harness (and the render tests) install, so a capture of the pane shows the item list
/// without anyone pressing "Check System". Never set in a release build.
@MainActor
public enum DiagnosticsDebugReport {
    public static var value: SystemCheckReport?
}
#endif

// MARK: - Rows

/// One line of the system check: a symbol, the localized title, the technical detail, and the result in words.
private struct CheckItemRow: View {
    let item: SystemCheckReport.Item

    @Environment(\.l10n) private var l10n

    var body: some View {
        let status = DiagnosticsText.status(item.status, l10n: l10n)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: DiagnosticsText.symbol(item.status))
                .foregroundStyle(DiagnosticsText.color(item.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DiagnosticsText.title(item.kind, l10n: l10n))
                if let detail = item.detail {
                    // Technical output of the check (file modes, signatures, counts), the same text the support
                    // report carries; it is data, not interface copy.
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.diagnostics.itemA11y(title: DiagnosticsText.title(item.kind, l10n: l10n), status: status))
        .accessibilityValue(item.detail ?? "")
    }
}

/// One account: its badge and name, the last refresh, the last probes as dots, what comes next, and "Refresh Now".
private struct AccountDiagnosticsRow: View {
    let presentation: AccountPresentation
    let diagnostics: AccountDiagnostics?
    let now: Date
    let onRefresh: () -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AccountBadge(style: presentation.style, provider: presentation.status.profile.provider, size: 24)
                Text(presentation.status.profile.label.value)
                Spacer(minLength: 8)
                Button(l10n.accounts.refreshNow) { onRefresh() }
                    .buttonStyle(.glass)
                    .frame(minHeight: SettingsMetrics.hitTarget)
                    // Every account row, and the Data format section, carry the same title; VoiceOver needs the name.
                    .accessibilityLabel(l10n.diagnostics.refreshAccountA11y(presentation.status.profile.label.value))
            }
            Text(DiagnosticsText.lastRefresh(diagnostics, provider: presentation.status.profile.provider, l10n: l10n))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProbeDots(probes: diagnostics?.recentProbes ?? [], provider: presentation.status.profile.provider)
            if !footnotes.isEmpty {
                Text(footnotes.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    /// What comes next and anything unusual: the next refresh, a slowed schedule, repeated failures.
    private var footnotes: [String] {
        guard let diagnostics else { return [] }
        var parts: [String] = []
        if let next = diagnostics.nextRefreshAt {
            let seconds = next.timeIntervalSince(now)
            parts.append(seconds <= 0
                ? l10n.usage.nextRefreshNow
                : l10n.usage.nextRefresh(in: l10n.format.durationCompact(seconds)))
        }
        if diagnostics.energyFactor > 1 {
            parts.append(l10n.diagnostics.slowedBy(DiagnosticsText.factor(diagnostics.energyFactor, l10n: l10n)))
        }
        if diagnostics.consecutiveFailures > 0 {
            parts.append(l10n.diagnostics.failuresInARow(diagnostics.consecutiveFailures))
        }
        return parts
    }
}

/// The last refreshes as small marks. The shape carries the outcome as well as the colour, and VoiceOver reads them
/// in order, so colour is never the only signal.
private struct ProbeDots: View {
    let probes: [ProbeRecord]
    let provider: ProviderKind

    @Environment(\.l10n) private var l10n

    /// The dots shown, oldest first.
    static let maximumDots = 8
    static let dotSize: CGFloat = 9

    private var shown: [ProbeRecord] {
        Array(probes.prefix(Self.maximumDots)).reversed()
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, probe in
                DiagnosticsText.shape(for: probe.outcome)
                    .fill(DiagnosticsText.color(for: probe.outcome), style: FillStyle(eoFill: true))
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
            if shown.isEmpty {
                Text(l10n.diagnostics.noRefreshYet)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.isEmpty
            ? l10n.diagnostics.noRefreshYet
            : l10n.diagnostics.recentRefreshesA11y(l10n.format.list(shown.map { DiagnosticsText.outcome($0.outcome, provider: provider, l10n: l10n) })))
    }
}

/// One provider CLI: where it is, which version, and who signed it.
private struct ToolRow: View {
    let provider: ProviderKind
    let diagnostics: ExecutableDiagnostics?

    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                SettingsSymbol(
                    systemImage: provider == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right",
                    tint: Theme.accent(for: provider)
                )
                Text(UsageFormat.providerName(provider))
                Spacer(minLength: 8)
                Text(diagnostics?.version.map { l10n.diagnostics.version($0) } ?? l10n.diagnostics.versionUnknown)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // A file path: data, shown as it is, with the home folder already abbreviated by the engine.
            Text(diagnostics?.displayPath ?? l10n.diagnostics.notInstalled)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(DiagnosticsText.signature(diagnostics?.signature ?? .notFound, l10n: l10n))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Words, symbols and shapes

/// Turns diagnostics values into the words, symbols and shapes the pane draws. Pure, so both languages are tested
/// without rendering.
enum DiagnosticsText {
    static func title(_ kind: SystemCheckItemKind, l10n: Localizer) -> String {
        let strings = l10n.diagnostics
        return switch kind {
        case .claudeExecutable: strings.itemClaudeTool
        case .codexExecutable: strings.itemCodexTool
        case .claudeProfile: strings.itemClaudeProfile
        case .codexProfile: strings.itemCodexProfile
        case .historyDatabase: strings.itemHistory
        case .settingsPermissions: strings.itemSettingsFile
        case .dataFolderPermissions: strings.itemDataFolder
        case .network: strings.itemNetwork
        case .notifications: strings.itemNotifications
        case .loginItem: strings.itemLoginItem
        case .shortcut: strings.itemShortcut
        case .widgetSnapshot: strings.itemWidget
        case .displays: strings.itemDisplays
        case .appLocation: strings.itemAppLocation
        case .crashReports: strings.itemCrashReports
        case .serviceStatus: strings.itemServiceStatus
        }
    }

    static func status(_ status: SystemCheckReport.Item.Status, l10n: Localizer) -> String {
        switch status {
        case .ok: l10n.diagnostics.statusOK
        case .note: l10n.diagnostics.statusNote
        case .warning: l10n.diagnostics.statusWarning
        case .failure: l10n.diagnostics.statusFailure
        }
    }

    static func symbol(_ status: SystemCheckReport.Item.Status) -> String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .note: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    static func color(_ status: SystemCheckReport.Item.Status) -> Color {
        switch status {
        case .ok: .green
        case .note: .secondary
        case .warning: .orange
        case .failure: .red
        }
    }

    static func signature(_ signature: ExecutableDiagnostics.Signature, l10n: Localizer) -> String {
        switch signature {
        case .trusted(let publisher, let teamID): l10n.diagnostics.signedBy(publisher: publisher, teamID: teamID)
        case .untrusted(let teamID): teamID.map { l10n.diagnostics.signedByOther(teamID: $0) } ?? l10n.diagnostics.signedByOtherUnknown
        case .unsigned: l10n.diagnostics.unsigned
        case .notFound: l10n.diagnostics.notInstalled
        case .invalid(let status): l10n.diagnostics.signatureCheckFailed(code: String(status))
        }
    }

    static func health(_ health: HistoryHealth, l10n: Localizer) -> String {
        switch health {
        case .ok: l10n.diagnostics.historyOK
        case .unavailable: l10n.diagnostics.historyUnavailable
        case .recoveredFromCorruption: l10n.diagnostics.historyRecovered
        case .readOnlyNewerSchema: l10n.diagnostics.historyReadOnly
        case .writesPaused: l10n.diagnostics.historyWritesPaused
        }
    }

    static func crashKind(_ kind: CrashReportSummary.Kind, l10n: Localizer) -> String {
        switch kind {
        case .crash: l10n.diagnostics.crashKindCrash
        case .hang: l10n.diagnostics.crashKindHang
        case .exception: l10n.diagnostics.crashKindException
        }
    }

    /// "1.5" or "2": a whole factor keeps no decimals.
    static func factor(_ value: Double, l10n: Localizer) -> String {
        l10n.format.decimal(value, fractionDigits: value == value.rounded() ? 0 : 1)
    }

    /// Megabytes from 1 MB up, kilobytes below.
    static func fileSize(_ bytes: Int64, l10n: Localizer) -> String {
        let kilobytes = Double(bytes) / 1_024
        return kilobytes >= 1_024
            ? l10n.diagnostics.megabytes(l10n.format.decimal(kilobytes / 1_024, fractionDigits: 1))
            : l10n.diagnostics.kilobytes(l10n.format.decimal(kilobytes, fractionDigits: 0))
    }

    /// "Last refresh 14:32 · took 2.4s · 3 limits", or why the last attempt brought nothing.
    static func lastRefresh(_ diagnostics: AccountDiagnostics?, provider: ProviderKind, l10n: Localizer) -> String {
        guard let probe = diagnostics?.recentProbes.first else { return l10n.diagnostics.noRefreshYet }
        let line = l10n.diagnostics.lastRefresh(
            at: l10n.format.clock(probe.startedAt),
            took: l10n.format.latency(probe.duration)
        )
        return "\(line) · \(outcome(probe.outcome, provider: provider, l10n: l10n))"
    }

    /// What one refresh attempt produced, in words.
    static func outcome(_ outcome: ProbeRecord.Outcome, provider: ProviderKind, l10n: Localizer) -> String {
        switch outcome {
        case .reading(let windowCount):
            return l10n.diagnostics.limitsRead(windowCount)
        case .failure(let kind):
            // The account's own issue wording, so a failed probe reads like the banner the user already knows.
            return UsageFormat.issue(TrackerIssue(kind: kind, detail: "", occurredAt: .distantPast), provider: provider, l10n: l10n)
        case .skipped(let reason):
            return l10n.diagnostics.skipped(skip(reason, l10n: l10n))
        }
    }

    static func skip(_ reason: ProbeRecord.SkipReason, l10n: Localizer) -> String {
        switch reason {
        case .offline: l10n.diagnostics.skipOffline
        case .signedOutWait: l10n.diagnostics.skipSignedOut
        case .logsFresh: l10n.diagnostics.skipLogsFresh
        case .pausedAfterFormatDrift: l10n.diagnostics.skipPaused
        }
    }

    /// A circle for a reading, a diamond for a failure, a ring for a skipped attempt: the shape says what the colour
    /// says, so the marks work without colour.
    static func shape(for outcome: ProbeRecord.Outcome) -> AnyShape {
        switch outcome {
        case .reading: AnyShape(Circle())
        case .failure: AnyShape(ProbeDiamondShape())
        case .skipped: AnyShape(ProbeRingShape())
        }
    }

    static func color(for outcome: ProbeRecord.Outcome) -> Color {
        switch outcome {
        case .reading: .green
        case .failure: .red
        case .skipped: .secondary
        }
    }
}

/// A square standing on its corner: the failure mark of the probe dots.
struct ProbeDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// A hollow circle (filled even-odd): the skipped mark of the probe dots.
struct ProbeRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addPath(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28)))
        return path
    }
}
