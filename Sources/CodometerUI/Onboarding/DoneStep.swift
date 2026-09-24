import CodometerCore
import CodometerL10n
import SwiftUI

/// Step 6: what the flow set up, and the button that starts tracking.
struct DoneStep: View {
    let model: OnboardingModel

    @Environment(\.l10n) private var l10n

    private var trackedCount: Int { model.store.settings.accounts.count(where: { $0.isEnabled }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: l10n.onboarding.doneTitle,
                message: trackedCount == 0 ? l10n.onboarding.doneNoAccounts : l10n.onboarding.doneAccounts(trackedCount),
                systemImage: "checkmark.seal.fill"
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary, id: \.text) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(l10n.onboarding.doneBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var summary: [(symbol: String, text: String)] {
        var items: [(String, String)] = [
            (
                model.store.settings.appearance.presentationStyle == .island ? "rectangle.topthird.inset.filled" : "rectangle.on.rectangle",
                model.store.settings.appearance.presentationStyle == .island
                    ? l10n.onboarding.styleIsland
                    : l10n.onboarding.styleFloatingCard
            ),
            DoneStep.notifications(model.notifications, l10n: l10n),
        ]
        if model.store.settings.general.launchesAtLogin {
            items.append(("power", l10n.general.openAtLogin))
        }
        return items.map { (symbol: $0.0, text: $0.1) }
    }

    /// The notification line of the summary. A permission nobody asked for yet is not "off in System Settings":
    /// nothing is switched off there, so that state gets its own words.
    static func notifications(_ authorization: NotificationAuthorization, l10n: Localizer) -> (String, String) {
        switch authorization {
        case .authorized, .provisional: ("bell.badge", l10n.onboarding.notificationsOn)
        case .denied: ("bell.slash", l10n.onboarding.notificationsOff)
        case .notDetermined: ("bell", l10n.onboarding.notificationsNotAsked)
        }
    }
}
