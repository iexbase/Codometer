import CodometerCore
import CodometerL10n
import SwiftUI

/// Step 2: the Claude Code and Codex profile folders on this Mac, each with a Track switch and what the filesystem
/// says about it.
///
/// Readiness is read once when the step appears and again on "Check Again": no timer runs here. During a first run
/// the engine has not started yet (no CLI is spawned before the flow ends), so the words come from file metadata.
struct FoundProfilesStep: View {
    let model: OnboardingModel

    @Environment(\.l10n) private var l10n

    private var rows: [FoundProfile] { model.foundProfiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                OnboardingHeader(title: l10n.onboarding.foundTitle, message: l10n.onboarding.foundBody)
                Button(l10n.onboarding.checkAgain) {
                    Task { await model.refreshReadiness() }
                }
                .buttonStyle(.glass)
            }
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            ProfileRow(row: row, home: model.homePath) { isTracked in
                                model.setTracked(row, isTracked, l10n: l10n)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let issue = model.issue {
                InlineIssue(message: issue)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .task { await model.refreshReadiness() }
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.onboarding.noProfilesTitle, systemImage: "questionmark.folder")
                .font(.callout.weight(.medium))
            Text(l10n.onboarding.noProfilesBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.4)))
        .accessibilityElement(children: .combine)
    }
}

/// One profile folder: provider glyph, label and path, the readiness in words, and the Track switch.
private struct ProfileRow: View {
    let row: FoundProfile
    let home: String
    let setTracked: (Bool) -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 12) {
            ProviderGlyph(provider: row.provider)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.callout.weight(.medium))
                Text(OnboardingAccounts.displayPath(row.directory.path, home: home))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            readiness
            Toggle(isOn: Binding(get: { row.isTracked }, set: { isOn in setTracked(isOn) })) {
                Text(l10n.onboarding.track)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(l10n.onboarding.trackA11y(row.label))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.4)))
        .accessibilityElement(children: .contain)
    }

    private var readiness: some View {
        Label(FoundProfilesCopy.readiness(row.state, provider: row.provider, l10n: l10n), systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
    }

    /// The symbol repeats what the words say, so colour is never the only signal.
    private var symbol: String {
        switch row.state {
        case .some(.signedIn): "checkmark.circle"
        case .some(.notSignedIn): "person.crop.circle.badge.questionmark"
        case .some(.missingFolder), .some(.notAProfile): "folder.badge.questionmark"
        case .some(.symlinkRefused): "link.badge.plus"
        case .none: "ellipsis.circle"
        }
    }
}

/// Readiness in words, never colour alone.
enum FoundProfilesCopy {
    static func readiness(_ state: ProfileReadiness.State?, provider: ProviderKind, l10n: Localizer) -> String {
        switch state {
        case .some(.signedIn(let plan)):
            if let plan { return l10n.onboarding.signedInPlan(plan) }
            return l10n.onboarding.signedIn
        case .some(.notSignedIn):
            return l10n.onboarding.notSignedIn
        case .some(.missingFolder):
            return l10n.onboarding.notInstalled(WidgetText.providerName(provider))
        case .some(.notAProfile):
            return l10n.onboarding.notAProfile
        case .some(.symlinkRefused):
            return l10n.onboarding.symlinkRefused
        case .none:
            return l10n.common.loading
        }
    }
}
