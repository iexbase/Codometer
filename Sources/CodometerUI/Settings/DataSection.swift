import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// General → History & Data: how long history is kept, exporting it, and erasing everything.
struct DataSection: View {
    let store: TrackerStore

    /// A shorter retention deletes readings at once, so it is confirmed first; the picker keeps its old value
    /// until then.
    @State private var pendingRetention: HistoryRetention?
    @State private var issue: String?
    @State private var controls = DataControls.shared
    @Environment(\.l10n) private var l10n

    private var retention: HistoryRetention { store.settings.general.historyRetention }

    var body: some View {
        Section {
            Picker(selection: Binding(get: { retention }, set: { choice in choose(choice) })) {
                ForEach(RetentionCopy.choices(including: retention), id: \.days) { choice in
                    Text(RetentionCopy.title(choice, l10n: l10n)).tag(choice)
                }
            } label: {
                SettingsRowLabel(
                    title: l10n.dataControls.retention,
                    subtitle: l10n.dataControls.retentionSubtitle,
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                )
            }
            .settingsControl(title: l10n.dataControls.retention, subtitle: l10n.dataControls.retentionSubtitle)
            .alert(l10n.dataControls.shrinkTitle, isPresented: shrinkAlert) {
                Button(l10n.common.cancel, role: .cancel) { pendingRetention = nil }
                Button(l10n.dataControls.shrinkConfirm, role: .destructive) { confirmShrink() }
            } message: {
                Text(l10n.dataControls.shrinkMessage)
            }

            // The status line belongs to the export row: as a row of its own it would draw an empty one with
            // separators around it while nothing has been exported yet.
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    Button(l10n.dataControls.export) { startExport() }
                        .buttonStyle(.glass)
                        .disabled(controls.export == .running)
                } label: {
                    SettingsRowLabel(
                        title: l10n.dataControls.exportRowTitle,
                        subtitle: l10n.dataControls.exportSubtitle,
                        systemImage: "square.and.arrow.up",
                        tint: .blue
                    )
                }
                ExportStatusRow(export: controls.export, reveal: revealExport)
                    .animation(Motion.content, value: controls.export)
            }

            LabeledContent {
                Button(l10n.dataControls.erase, role: .destructive) { controls.showsEraseSheet = true }
                    .buttonStyle(.glass)
            } label: {
                SettingsRowLabel(
                    title: l10n.dataControls.eraseRowTitle,
                    subtitle: l10n.dataControls.eraseSubtitle,
                    systemImage: "trash",
                    tint: .red
                )
            }
            .sheet(isPresented: $controls.showsEraseSheet) {
                EraseDataSheet(
                    exportFirst: {
                        controls.showsEraseSheet = false
                        startExport()
                    },
                    erase: { relaunch in
                        controls.showsEraseSheet = false
                        store.actions.eraseAllData(relaunch)
                    },
                    cancel: { controls.showsEraseSheet = false }
                )
                .environment(\.l10n, l10n)
                .environment(\.locale, l10n.locale)
            }

            if let issue {
                InlineIssue(message: issue)
                    .animation(Motion.content, value: issue)
            }
        } header: {
            Text(l10n.dataControls.sectionTitle)
        } footer: {
            SectionNote(l10n.dataControls.sectionNote)
        }
    }

    private var shrinkAlert: Binding<Bool> {
        Binding(get: { pendingRetention != nil }, set: { shown in if !shown { pendingRetention = nil } })
    }

    private func choose(_ choice: HistoryRetention) {
        guard choice != retention else { return }
        if choice < retention {
            pendingRetention = choice
        } else {
            apply(choice)
        }
    }

    private func confirmShrink() {
        guard let choice = pendingRetention else { return }
        pendingRetention = nil
        apply(choice)
    }

    private func apply(_ choice: HistoryRetention) {
        issue = store.updateSettings { $0.general.historyRetention = choice }
            .map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
    }

    private func startExport() {
        controls.exportIdle()
        store.actions.exportHistory()
    }

    private func revealExport(_ url: URL) {
        store.actions.revealInFinder(url)
    }
}

/// Picker titles for the retention choices: the four offered periods, plus a hand-edited value shown as days.
enum RetentionCopy {
    /// The offered choices, with `current` inserted in order when it is not one of them.
    static func choices(including current: HistoryRetention) -> [HistoryRetention] {
        let offered = HistoryRetention.choices
        guard !offered.contains(current) else { return offered }
        return (offered + [current]).sorted()
    }

    static func title(_ retention: HistoryRetention, l10n: Localizer) -> String {
        switch retention.days {
        case 7: l10n.dataControls.weeks(1)
        case 14: l10n.dataControls.weeks(2)
        case 35: l10n.dataControls.weeks(5)
        case 90: l10n.dataControls.months(3)
        default: l10n.dataControls.days(retention.days)
        }
    }
}

/// The line under "Export History…": progress, the result with "Show in Finder", or why it failed.
///
/// It always takes the height and width of the widest result, so starting an export never moves the rows below it.
private struct ExportStatusRow: View {
    let export: DataControls.Export
    let reveal: (URL) -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack(alignment: .leading) {
            Text(l10n.dataControls.exportResultTemplate)
                .font(.callout)
                .hidden()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch export {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(l10n.dataControls.exporting)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(l10n.dataControls.exporting)
        case let .finished(rows, destination):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(DataControls.exportedRows(rows, l10n: l10n))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(l10n.dataControls.showInFinder) { reveal(destination) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        case .failed(let error):
            Label(DataControls.message(for: error, l10n: l10n), systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The data controls' transient state, shared with the app shell.
///
/// `TrackerActions.exportHistory()` carries no result back and `TrackerStore` holds persisted settings and engine
/// state only, so this one main-actor object is the seam: the section starts an export, `AppController+Data` runs
/// the save panel and the export and reports progress here, and the debug harness opens the erase sheet through it.
@MainActor
@Observable
public final class DataControls {
    public enum Export: Equatable, Sendable {
        case idle
        case running
        case finished(rows: Int, destination: URL)
        case failed(HistoryExportError)
    }

    public static let shared = DataControls()

    public private(set) var export: Export = .idle
    /// The erase sheet over the General pane; the section owns the presentation, the shell and the harness open it.
    public var showsEraseSheet = false

    init() {}

    public func exportIdle() {
        set(.idle)
    }

    public func exportStarted() {
        set(.running)
    }

    public func exportFinished(rows: Int, destination: URL) {
        set(.finished(rows: rows, destination: destination))
    }

    /// A cancelled export is not a failure: the row goes quiet again.
    public func exportFailed(_ error: HistoryExportError) {
        set(error == .cancelled ? .idle : .failed(error))
    }

    private func set(_ phase: Export) {
        guard phase != export else { return }
        export = phase
    }

    /// "Exported 12,480 rows", with the count grouped by the interface locale.
    nonisolated public static func exportedRows(_ count: Int, l10n: Localizer) -> String {
        l10n.dataControls.exportedRows(count, formattedCount: count.formatted(.number.locale(l10n.locale)))
    }

    /// Why an export did not happen, in words. A cancelled export never reaches this.
    nonisolated public static func message(for error: HistoryExportError, l10n: Localizer) -> String {
        switch error {
        case .historyUnavailable: l10n.dataControls.exportFailedHistoryUnavailable
        case .destinationExists: l10n.dataControls.exportFailedDestinationExists
        case .writeFailed: l10n.dataControls.exportFailedWrite
        case .cancelled: l10n.dataControls.exportFailedWrite
        }
    }
}
