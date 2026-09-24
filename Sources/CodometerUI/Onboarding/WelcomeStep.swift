import CodometerCore
import CodometerL10n
import SwiftUI

/// Step 1: what Codometer is, what it never does, and the language it speaks.
///
/// The language picker is here so someone who does not read English is not stuck in it on a fresh install; it
/// switches Codometer's own text at once.
struct WelcomeStep: View {
    let model: OnboardingModel

    @Environment(\.l10n) private var l10n

    private var promises: [(symbol: String, title: String, detail: String)] {
        [
            ("desktopcomputer", l10n.onboarding.promiseLocal, l10n.onboarding.promiseLocalDetail),
            ("lock.shield.fill", l10n.onboarding.promiseNoSecrets, l10n.onboarding.promiseNoSecretsDetail),
            ("hand.raised.fill", l10n.onboarding.promiseNoChanges, l10n.onboarding.promiseNoChangesDetail),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                OnboardingHeader(title: l10n.onboarding.welcomeTitle, message: l10n.onboarding.welcomeBody)
                languagePicker
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(promises, id: \.title) { promise in
                    HStack(alignment: .top, spacing: 12) {
                        SettingsSymbol(systemImage: promise.symbol, tint: .accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promise.title)
                                .font(.callout.weight(.medium))
                            Text(promise.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var languagePicker: some View {
        Picker(selection: Binding(
            get: { model.store.settings.general.language },
            set: { WelcomeStep.setLanguage($0, in: model.store) }
        )) {
            ForEach(LanguagePreference.allCases) { preference in
                Text(WelcomeStep.name(preference, l10n: l10n)).tag(preference)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(l10n.languageSettings.title)
    }

    /// English and Russian are named in their own language, whatever the interface language.
    static func name(_ preference: LanguagePreference, l10n: Localizer) -> String {
        switch preference {
        case .english: l10n.languageSettings.nativeName(.en)
        case .russian: l10n.languageSettings.nativeName(.ru)
        case .system: l10n.languageSettings.systemLanguage
        }
    }

    /// Saves the chosen language; `TrackerStore` rebuilds its localizer, so the window switches at once.
    static func setLanguage(_ preference: LanguagePreference, in store: TrackerStore) {
        store.updateSettings { $0.general.language = preference }
    }
}
