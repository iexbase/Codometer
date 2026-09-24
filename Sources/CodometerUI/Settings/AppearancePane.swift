import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// How the island looks and what it reveals: glass, data, ring colours and e-mail privacy.
struct AppearancePane: View {
    let store: TrackerStore
    @Binding var stageOptions: IslandStageOptions

    @State private var issue: String?
    @Environment(\.l10n) private var l10n

    private var appearance: AppearanceSettings { store.settings.appearance }

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    title: l10n.settingsPanes.appearance,
                    subtitle: l10n.appearance.paneSubtitle,
                    systemImage: "paintpalette.fill",
                    tint: .pink
                )
                if let issue {
                    SettingsIssueBanner(message: issue) { self.issue = nil }
                }
            }

            Section {
                IslandStage(store: store, options: $stageOptions)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appearance.glowsWithUrgency },
                    set: { isOn in apply { $0.appearance.glowsWithUrgency = isOn } }
                )) {
                    SettingsRowLabel(
                        title: l10n.appearance.urgencyGlow,
                        subtitle: l10n.appearance.urgencyGlowSubtitle,
                        systemImage: "sun.max.fill",
                        tint: .orange
                    )
                }
                .settingsControl(title: l10n.appearance.urgencyGlow, subtitle: l10n.appearance.urgencyGlowSubtitle)
            } header: {
                Text(l10n.appearance.glassTitle)
            }

            Section(l10n.appearance.detailsTitle) {
                Picker(selection: Binding(
                    get: { appearance.deckDetail },
                    set: { detail in apply { $0.appearance.deckDetail = detail } }
                )) {
                    ForEach(DeckDetail.allCases) { detail in
                        Text(Self.title(detail, l10n: l10n)).tag(detail)
                    }
                } label: {
                    SettingsRowLabel(title: l10n.appearance.expandedView, systemImage: "rectangle.expand.vertical", tint: .purple)
                }
                .pickerStyle(.segmented)
                .settingsControl(title: l10n.appearance.expandedView)
                SectionNote(Self.explanation(appearance.deckDetail, l10n: l10n))
                    .contentTransition(.opacity)
                    .animation(Motion.content, value: appearance.deckDetail)
                Picker(selection: Binding(
                    get: { appearance.resetTextStyle },
                    set: { style in apply { $0.appearance.resetTextStyle = style } }
                )) {
                    Text(l10n.appearance.countdownSample(l10n.format.durationCompact(Self.sampleCountdown))).tag(ResetTextStyle.countdown)
                    Text(l10n.appearance.clockSample(Self.sampleResetDate(in: l10n.calendar))).tag(ResetTextStyle.clockTime)
                } label: {
                    SettingsRowLabel(title: l10n.appearance.resetTime, systemImage: "clock.arrow.circlepath", tint: .blue)
                }
                .pickerStyle(.segmented)
                .settingsControl(title: l10n.appearance.resetTime)
                Toggle(isOn: Binding(
                    get: { appearance.showsSecondaryRing },
                    set: { isOn in apply { $0.appearance.showsSecondaryRing = isOn } }
                )) {
                    SettingsRowLabel(title: l10n.appearance.weeklyRings, systemImage: "circle.circle", tint: .indigo)
                }
                .settingsControl(title: l10n.appearance.weeklyRings)
                Toggle(isOn: Binding(
                    get: { appearance.showsPace },
                    set: { isOn in apply { $0.appearance.showsPace = isOn } }
                )) {
                    SettingsRowLabel(title: l10n.appearance.pace, systemImage: "gauge.with.needle.fill", tint: .teal)
                }
                .settingsControl(title: l10n.appearance.pace)
                Toggle(isOn: Binding(
                    get: { appearance.showsForecast },
                    set: { isOn in apply { $0.appearance.showsForecast = isOn } }
                )) {
                    SettingsRowLabel(
                        title: l10n.appearance.forecast,
                        subtitle: l10n.appearance.forecastSubtitle,
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .mint
                    )
                }
                .settingsControl(title: l10n.appearance.forecast, subtitle: l10n.appearance.forecastSubtitle)
                Toggle(isOn: Binding(
                    get: { appearance.celebratesResets },
                    set: { isOn in apply { $0.appearance.celebratesResets = isOn } }
                )) {
                    SettingsRowLabel(
                        title: l10n.appearance.resets,
                        subtitle: l10n.appearance.resetsSubtitle,
                        systemImage: "sparkles",
                        tint: .green
                    )
                }
                .settingsControl(title: l10n.appearance.resets, subtitle: l10n.appearance.resetsSubtitle)
            }

            Section {
                BandLegend(bands: appearance.bands)
                    .frame(height: 30)
                thresholdSlider(l10n.appearance.yellowFrom, value: appearance.bands.watch.value, range: 5...95) { value in
                    apply { (settings: inout AppSettings) throws(ValidationError) in
                        let watch = try Percentage(validating: value)
                        let critical = max(settings.appearance.bands.critical, try Percentage(validating: min(100, value + 5)))
                        settings.appearance.bands = try BandThresholds(watch: watch, critical: critical)
                    }
                }
                thresholdSlider(l10n.appearance.redFrom, value: appearance.bands.critical.value, range: 10...100) { value in
                    apply { (settings: inout AppSettings) throws(ValidationError) in
                        let critical = try Percentage(validating: value)
                        let watch = min(settings.appearance.bands.watch, try Percentage(validating: max(1, value - 5)))
                        settings.appearance.bands = try BandThresholds(watch: watch, critical: critical)
                    }
                }
            } header: {
                Text(l10n.appearance.ringColorsTitle)
            } footer: {
                SectionNote(l10n.appearance.ringColorsFooter)
            }

            Section {
                Picker(selection: Binding(
                    get: { appearance.emailVisibility },
                    set: { visibility in apply { $0.appearance.emailVisibility = visibility } }
                )) {
                    ForEach(EmailVisibility.allCases) { visibility in
                        Text(title(visibility)).tag(visibility)
                    }
                } label: {
                    SettingsRowLabel(title: l10n.appearance.emailAddress, systemImage: "envelope.fill", tint: .blue)
                }
                .pickerStyle(.segmented)
                .settingsControl(title: l10n.appearance.emailAddress)
                EmailVisibilityExample(address: exampleAddress, visibility: appearance.emailVisibility)
            } header: {
                Text(l10n.appearance.privacyTitle)
            } footer: {
                SectionNote(l10n.appearance.privacyFooter)
            }
        }
        .formStyle(.grouped)
        .animation(Motion.content, value: issue)
    }

    /// The first known address of a tracked account, so the example shows what the user will actually see.
    private var exampleAddress: String {
        store.state.accounts.lazy.compactMap { $0.identity?.email }.first { !$0.isEmpty } ?? SettingsCopy.sampleEmail
    }

    /// The example countdown of the reset-time picker: 2 h 14 min.
    static let sampleCountdown: TimeInterval = 2 * 3_600 + 14 * 60

    /// The example reset of the clock choice: a Friday at 12:10 in the calendar's time zone.
    static func sampleResetDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12, minute: 10)) ?? Date(timeIntervalSince1970: 1_789_733_400)
    }

    /// Width of the value next to a colour slider; `percentValueTemplate` must fit (`SettingsPanesCopyTests`).
    static let percentValueWidth: CGFloat = 44
    /// The widest value a colour slider shows.
    static let percentValueTemplate: Double = 100

    private func title(_ visibility: EmailVisibility) -> String {
        switch visibility {
        case .visible: l10n.appearance.emailShow
        case .masked: l10n.appearance.emailMask
        case .hidden: l10n.appearance.emailHide
        }
    }

    private func thresholdSlider(_ title: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { value }, set: { onChange($0.rounded()) }), in: range, step: 1)
                    .accessibilityLabel(title)
                    .accessibilityValue(l10n.format.percent(value))
                Text(l10n.format.percentCompact(value))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(width: Self.percentValueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    static func title(_ detail: DeckDetail, l10n: Localizer) -> String {
        switch detail {
        case .essentials: l10n.appearance.detailEssentials
        case .full: l10n.appearance.detailFull
        }
    }

    /// The line under the detail picker.
    static func explanation(_ detail: DeckDetail, l10n: Localizer) -> String {
        switch detail {
        case .essentials: l10n.appearance.detailEssentialsExplanation
        case .full: l10n.appearance.detailFullExplanation
        }
    }

    private func apply(_ change: (inout AppSettings) throws(ValidationError) -> Void) {
        issue = store.updateSettings(change).map { SettingsCopy.settingsMessage(for: $0, l10n: l10n) }
    }
}

/// "Looks like: e••••e@test.com", updated in place as the setting changes.
private struct EmailVisibilityExample: View {
    let address: String
    let visibility: EmailVisibility

    @Environment(\.l10n) private var l10n

    var body: some View {
        let shown = UsageFormat.email(address, visibility: visibility)
        let example = shown ?? l10n.appearance.emailNotShown
        HStack(spacing: 10) {
            Image(systemName: visibility == .hidden ? "eye.slash" : "eye")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))
            Text(l10n.appearance.emailPreview)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(example)
                // Addresses are monospaced so masking lines up; the "not shown" note is ordinary text.
                .font(shown == nil ? .callout : .callout.monospaced())
                .foregroundStyle(visibility == .hidden ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: Capsule())
            Spacer(minLength: 0)
        }
        .animation(Motion.content, value: visibility)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.appearance.emailPreviewA11y(example))
    }
}

private struct BandLegend: View {
    let bands: BandThresholds

    @Environment(\.l10n) private var l10n

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let watch = CGFloat(bands.watch.value / 100)
            let critical = CGFloat(bands.critical.value / 100)
            HStack(spacing: 3) {
                segment(.ample, width: width * watch - 3, label: l10n.appearance.bandRange(from: wholeNumber(0), to: percent(bands.watch.value)))
                segment(.watch, width: width * (critical - watch) - 3, label: l10n.appearance.bandRange(from: wholeNumber(bands.watch.value), to: percent(bands.critical.value)))
                segment(.critical, width: width * (1 - critical), label: l10n.appearance.bandAbove(percent(bands.critical.value)))
            }
            .animation(Motion.snappy, value: bands)
        }
        .accessibilityElement()
        .accessibilityLabel(l10n.appearance.bandsA11y(watch: l10n.format.percent(bands.watch.value), critical: l10n.format.percent(bands.critical.value)))
    }

    /// A band's upper end with its sign: "60%" (drawn numerals, no space in any language).
    private func percent(_ value: Double) -> String {
        l10n.format.percentCompact(value)
    }

    /// A band's lower end without the sign, as in "60–85%".
    private func wholeNumber(_ value: Double) -> String {
        l10n.format.decimal(value, fractionDigits: 0)
    }

    /// Narrower segments drop their label instead of shrinking it below the 10.5 pt floor; the sliders
    /// below and the accessibility label still give every value.
    private static let minimumLabelledWidth: CGFloat = 48

    private func segment(_ band: UsageBand, width: CGFloat, label: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: Theme.colors(for: band), startPoint: .leading, endPoint: .trailing))
            .frame(width: max(0, width))
            .overlay {
                Text(label)
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.875)
                    .padding(.horizontal, 4)
                    .opacity(width >= Self.minimumLabelledWidth ? 1 : 0)
            }
    }
}
