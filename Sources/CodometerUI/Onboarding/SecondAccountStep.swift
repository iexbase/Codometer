import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// Step 4: the optional second-account wizard.
///
/// Codometer never automates any of this: it shows the commands, copies them, and watches the folder. The watch is
/// a two-second check that runs only while the waiting stage is on screen, in a task the view cancels on disappear.
struct SecondAccountStep: View {
    let model: OnboardingModel

    @State private var copied: String?
    @Environment(\.l10n) private var l10n

    private var wizard: SecondAccountWizard { model.wizard }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(title: title, message: message)
            stage
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch wizard.stage {
        case .intro, .service: l10n.onboarding.secondAccountTitle
        case .name: l10n.onboarding.profileName
        case .signIn: l10n.onboarding.signInTitle
        case .waiting: l10n.onboarding.waitingTitle
        case .detected: l10n.onboarding.detectedTitle
        }
    }

    private var message: String {
        switch wizard.stage {
        case .intro, .service: l10n.onboarding.secondAccountBody
        case .name: l10n.onboarding.profileNameRule
        case .signIn: wizard.provider == .claude ? l10n.onboarding.signInClaudeNote : l10n.onboarding.signInCodexNote
        case .waiting: l10n.onboarding.waitingBody
        case .detected: l10n.onboarding.secondAccountBody
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch wizard.stage {
        case .intro: intro
        case .service: service
        case .name: name
        case .signIn: signIn
        case .waiting: waiting
        case .detected: detected
        }
    }

    // MARK: Stages

    private var intro: some View {
        HStack(spacing: 10) {
            Button(l10n.onboarding.secondAccountStart) { model.startWizard() }
                .buttonStyle(.glassProminent)
            Text(l10n.onboarding.secondAccountOptional)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The footer's Continue moves on from here, so the choice is a picker, not a pair of buttons.
    private var service: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.onboarding.chooseService)
                .font(.callout.weight(.medium))
            Picker(selection: Binding(get: { model.wizard.provider }, set: { provider in model.setService(provider) })) {
                ForEach(ProviderKind.allCases) { provider in
                    Text(WidgetText.providerName(provider)).tag(provider)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Leading, or the control floats in the middle of its reserved width, out of line with everything else.
            .frame(width: 240, alignment: .leading)
            .accessibilityLabel(l10n.onboarding.chooseService)
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(text: Binding(get: { wizard.suffixText }, set: { text in model.setSuffixText(text) })) {
                Text(l10n.onboarding.profileName)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .accessibilityLabel(l10n.onboarding.profileName)
            Text(folderNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderNote: String {
        guard let folder = wizard.folderDisplayPath else { return l10n.onboarding.profileNameInvalid }
        if case .some = wizard.existingState(readiness: model.readiness, home: model.homePath) {
            return l10n.onboarding.profileFolderTaken
        }
        return l10n.onboarding.profileFolderNote(folder)
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(wizard.commands, id: \.self) { command in
                commandRow(command)
            }
            Label(l10n.onboarding.signInNoAutomation, systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                withAnimation(Motion.snappy) { copied = command }
            } label: {
                Image(systemName: copied == command ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .help(l10n.common.copy)
            .accessibilityLabel(l10n.accounts.copyCommandA11y(WidgetText.providerName(wizard.provider)))
            .accessibilityValue(copied == command ? l10n.accounts.copied : "")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
    }

    private var waiting: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(wizard.folderDisplayPath ?? "")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.onboarding.waitingTitle)
        // The only periodic work in the flow, and only while this stage is on screen.
        .task(id: wizard.folderDisplayPath) {
            while !Task.isCancelled {
                await model.refreshReadiness()
                guard model.wizard.stage == .waiting else { return }
                try? await Task.sleep(for: OnboardingModel.readinessInterval, tolerance: .milliseconds(200))
            }
        }
    }

    private var detected: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(wizard.folderDisplayPath ?? "")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(l10n.onboarding.accountName)
                    .font(.callout)
                TextField(text: Binding(get: { wizard.label }, set: { text in model.setWizardLabel(text) })) {
                    Text(l10n.onboarding.accountName)
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityLabel(l10n.onboarding.accountName)
                if !model.store.settings.groups.isEmpty {
                    groupPicker
                }
            }
            if let issue = model.issue {
                InlineIssue(message: issue)
            }
            Button(l10n.accounts.trackAccount) { model.addWizardAccount(l10n: l10n) }
                .buttonStyle(.glassProminent)
        }
    }

    private var groupPicker: some View {
        Picker(selection: Binding(get: { model.wizard.groupID }, set: { id in model.setWizardGroup(id) })) {
            Text(l10n.groups.noGroup).tag(AccountGroupID?.none)
            ForEach(model.store.settings.groups) { group in
                Text(group.name.value).tag(AccountGroupID?.some(group.id))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .frame(width: 150)
        .accessibilityLabel(l10n.groups.group)
    }
}
