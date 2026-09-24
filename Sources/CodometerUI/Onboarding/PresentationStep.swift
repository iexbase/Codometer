import CodometerCore
import CodometerL10n
import SwiftUI

/// Step 3: island or floating card, which edge it lives on, what opens it, and whether it blends into the notch.
///
/// The preview keeps one size for every choice, so changing a picker never resizes the step.
struct PresentationStep: View {
    let model: OnboardingModel

    @Environment(\.l10n) private var l10n

    private var appearance: AppearanceSettings { model.store.settings.appearance }
    /// The notch toggle appears only where there is a notch to blend into.
    private var hasNotch: Bool { model.store.displays.contains { $0.notch != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeader(title: l10n.onboarding.presentationTitle, message: l10n.onboarding.presentationBody)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    labelled(l10n.onboarding.style) {
                        Picker(selection: Binding(
                            get: { appearance.presentationStyle },
                            set: { model.store.actions.switchPresentationStyle($0) }
                        )) {
                            Text(l10n.onboarding.styleIsland).tag(PresentationStyle.island)
                            Text(l10n.onboarding.styleFloatingCard).tag(PresentationStyle.floatingCard)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel(l10n.onboarding.style)
                    }
                    labelled(l10n.onboarding.edge) {
                        Picker(selection: Binding(
                            get: { appearance.edge },
                            set: { edge in model.store.updateSettings { $0.appearance.edge = edge } }
                        )) {
                            Text(l10n.placement.top).tag(ScreenEdge.top)
                            Text(l10n.placement.bottom).tag(ScreenEdge.bottom)
                            Text(l10n.placement.left).tag(ScreenEdge.left)
                            Text(l10n.placement.right).tag(ScreenEdge.right)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel(l10n.onboarding.edge)
                        .disabled(appearance.presentationStyle != .island)
                    }
                    labelled(l10n.placement.expandOn) {
                        Picker(selection: Binding(
                            get: { appearance.openTrigger },
                            set: { trigger in model.store.updateSettings { $0.appearance.openTrigger = trigger } }
                        )) {
                            Text(l10n.placement.hover).tag(IslandOpenTrigger.hover)
                            Text(l10n.placement.click).tag(IslandOpenTrigger.click)
                            Text(l10n.placement.hoverOrClick).tag(IslandOpenTrigger.hoverOrClick)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel(l10n.placement.expandOn)
                    }
                    if hasNotch {
                        Toggle(isOn: Binding(
                            get: { appearance.notchFusion == .automatic },
                            set: { on in model.store.updateSettings { $0.appearance.notchFusion = on ? .automatic : .off } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.onboarding.notchFusion)
                                Text(l10n.onboarding.notchFusionDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityLabel(l10n.onboarding.notchFusion)
                        .accessibilityHint(l10n.onboarding.notchFusionDetail)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 310)

                preview
                    .frame(width: 258, height: PresentationStep.previewHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(l10n.onboarding.previewA11y)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    static let previewHeight: CGFloat = 176

    @ViewBuilder
    private var preview: some View {
        switch appearance.presentationStyle {
        case .island:
            OnboardingStagePreview(edge: appearance.edge, offset: appearance.offset, style: appearance.style)
        case .floatingCard:
            CardStage(store: model.store)
        }
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
        }
    }
}
