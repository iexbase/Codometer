import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// Notices about Codometer's own data (settings recovered, repaired or read-only, history problems, data left in the
/// former folder), above the Settings panes and once at the top of the menu bar popover.
///
/// Each notice stays until it is dismissed. Technical reasons never reach the user: `AppNotice` carries raw SQLite and
/// `errno` text, which is logged, while the banner shows a fixed phrase and, where it helps, a file name.
struct AppNoticeBanner: View {
    /// Where the banner is drawn: the Settings detail column, or the deck at the top of the popover.
    enum Placement {
        case settings
        /// Scaled with the deck's metrics and narrower.
        case deck(IslandMetrics)

        var scale: CGFloat {
            switch self {
            case .settings: 1
            case .deck(let metrics): metrics.scale
            }
        }
    }

    let store: TrackerStore
    var placement: Placement = .settings

    @Environment(\.l10n) private var l10n

    var body: some View {
        let notices = store.notices
        VStack(spacing: 8 * placement.scale) {
            ForEach(notices) { notice in
                row(AppNoticeText(notice, l10n: l10n), id: notice.id)
            }
        }
        .padding(notices.isEmpty ? .init() : insets)
        .animation(Motion.content, value: notices)
    }

    private var insets: EdgeInsets {
        switch placement {
        case .settings: EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20)
        case .deck: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }
    }

    private func row(_ text: AppNoticeText, id: AppNotice.ID) -> some View {
        let scale = placement.scale
        return HStack(alignment: .top, spacing: 10 * scale) {
            Image(systemName: text.systemImage)
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 20 * scale, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(text.title)
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(text.body)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reveal = text.reveal {
                    Button {
                        switch reveal {
                        case .dataFolder: store.actions.revealDataFolder()
                        case .folder(let url): store.actions.revealInFinder(url)
                        }
                    } label: {
                        Text(l10n.recovery.showInFinder)
                            .font(.system(size: 12 * scale, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(minHeight: 24, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 4 * scale)
            Button {
                store.dismissNotice(id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(l10n.settingsPanes.dismiss)
            .accessibilityLabel(l10n.settingsPanes.dismissMessageA11y)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.recovery.noticeA11y(title: text.title))
    }
}

/// One notice as the words the user reads, with the file the "Show in Finder" button opens.
///
/// Pure, so both languages are covered by tests and by the gated renders.
struct AppNoticeText: Equatable {
    /// What the notice's "Show in Finder" button opens.
    enum Reveal: Equatable {
        /// Codometer's own data folder, where the backup the notice mentions was written.
        case dataFolder
        /// A folder outside it, such as the one the app's former name used.
        case folder(URL)
    }

    let title: String
    let body: String
    let systemImage: String
    /// Where "Show in Finder" leads, when there is something worth opening.
    let reveal: Reveal?

    init(_ notice: AppNotice, l10n: Localizer, homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        let words = l10n.recovery
        switch notice {
        case .settingsRecovered(let backupFileName):
            title = words.settingsRecoveredTitle
            body = words.settingsRecoveredBody(backupFileName: backupFileName)
            systemImage = "arrow.counterclockwise.circle.fill"
            reveal = .dataFolder
        case .settingsRepaired(let count):
            title = words.settingsRepairedTitle
            body = words.settingsRepairedBody(count: count)
            systemImage = "wrench.adjustable.fill"
            reveal = .dataFolder
        case .settingsReadOnly:
            title = words.settingsReadOnlyTitle
            body = words.settingsReadOnlyBody
            systemImage = "lock.fill"
            reveal = nil
        case .history(let health):
            switch health {
            case .ok, .unavailable:
                title = words.historyUnavailableTitle
                body = words.historyUnavailableBody
                systemImage = "chart.bar.xaxis"
                reveal = nil
            case .recoveredFromCorruption(let backupFileName):
                title = words.historyRecoveredTitle
                body = words.historyRecoveredBody(backupFileName: backupFileName)
                systemImage = "arrow.counterclockwise.circle.fill"
                reveal = .dataFolder
            case .readOnlyNewerSchema:
                title = words.historyReadOnlyTitle
                body = words.historyReadOnlyBody
                systemImage = "lock.fill"
                reveal = nil
            case .writesPaused:
                title = words.historyPausedTitle
                body = words.historyPausedBody
                systemImage = "externaldrive.badge.exclamationmark"
                reveal = nil
            }
        }
    }
}
