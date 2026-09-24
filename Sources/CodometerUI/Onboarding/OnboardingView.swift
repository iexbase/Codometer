import CodometerCore
import CodometerL10n
import AppKit
import SwiftUI

/// The welcome flow: a fixed-size window with a step indicator, the current step, and one footer.
///
/// Nothing here resizes. The content area keeps `Layout.contentHeight` whatever the step shows, and the footer's
/// primary button is as wide as the longest label in the current language, so stepping through never nudges the
/// layout. Escape goes one step back, or skips on the first step.
public struct OnboardingView: View {
    @State private var model: OnboardingModel
    @State private var announcedStep: OnboardingStep?
    @Environment(\.l10n) private var l10n

    public init(model: OnboardingModel) {
        _model = State(initialValue: model)
    }

    enum Layout {
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 540
        static let horizontalPadding: CGFloat = 32
        /// Clears the transparent title bar and its close button.
        static let indicatorTop: CGFloat = 34
    }

    public var body: some View {
        VStack(spacing: 0) {
            indicator
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Layout.horizontalPadding)
            Divider()
            footer
        }
        .frame(width: Layout.windowWidth, height: Layout.windowHeight)
        .background(.background)
        .onExitCommand { model.escape() }
        .onChange(of: model.step) { _, step in announce(step) }
        .onAppear { announcedStep = model.step }
    }

    // MARK: Chrome

    private var indicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= model.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: step == model.step ? 22 : 8, height: 6)
                    .animation(Motion.content, value: model.step)
            }
            Spacer(minLength: 0)
            Text(l10n.onboarding.step(model.step.number, of: OnboardingStep.total))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.indicatorTop)
        .padding(.bottom, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.onboarding.step(model.step.number, of: OnboardingStep.total))
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .found: FoundProfilesStep(model: model)
        case .presentation: PresentationStep(model: model)
        case .secondAccount: SecondAccountStep(model: model)
        case .notifications: NotificationsStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.step != .done {
                Button(l10n.onboarding.skip) { model.skip() }
                    .buttonStyle(.glass)
            }
            Spacer(minLength: 0)
            Button(l10n.onboarding.back) { model.back() }
                .buttonStyle(.glass)
                .disabled(!model.flow.canGoBack)
                .opacity(model.flow.canGoBack ? 1 : 0.35)
            ZStack {
                // Reserves the widest primary label in this language, so the button never resizes between steps.
                Text(l10n.onboarding.primaryButtonTemplate)
                    .padding(.horizontal, 14)
                    .hidden()
                Button(primaryTitle) { model.next() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 16)
    }

    private var primaryTitle: String {
        model.flow.isLastStep ? l10n.onboarding.start : l10n.onboarding.continueAction
    }

    /// VoiceOver hears "Step 2 of 6" when the step changes, and only then.
    private func announce(_ step: OnboardingStep) {
        guard announcedStep != step else { return }
        announcedStep = step
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: l10n.onboarding.step(step.number, of: OnboardingStep.total),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}

/// A step's title and explanation, laid out the same way on every step.
struct OnboardingHeader: View {
    let title: String
    let message: String
    var systemImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let systemImage {
                SettingsSymbol(systemImage: systemImage, tint: .accentColor, size: 40)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}
