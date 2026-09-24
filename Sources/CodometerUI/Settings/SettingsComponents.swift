import CodometerCore
import CodometerL10n
import Foundation
import SwiftUI

/// The large header at the top of every pane.
struct PaneHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsSymbol(systemImage: systemImage, tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A System Settings style icon tile: a white symbol on a tinted, softly lit rounded square.
struct SettingsSymbol: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        let corner = size * 0.27
        let isLarge = size > 30
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tint.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                                lineWidth: isLarge ? 1 : 0.75
                            )
                    }
            }
            .shadow(color: tint.opacity(isLarge ? 0.35 : 0.18), radius: isLarge ? 8 : 1.5, y: isLarge ? 3 : 0.5)
            .accessibilityHidden(true)
    }
}

/// A row title with an icon tile and an optional explanation underneath.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsSymbol(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    /// Names a settings control after its row title for VoiceOver, with the row's explanation, if any, as the hint.
    /// A form draws the title beside the control, but VoiceOver does not take it as the control's name.
    func settingsControl(title: String, subtitle: String? = nil) -> some View {
        accessibilityLabel(title)
            .accessibilityHint(subtitle ?? "")
    }
}

/// Explanatory text under a section, one step larger than the system footer so it stays readable.
struct SectionNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A rejected change, shown where the user made it.
struct InlineIssue: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// A dismissible notice for a rejected change that has no field of its own.
struct SettingsIssueBanner: View {
    let message: String
    let onDismiss: () -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(l10n.settingsPanes.dismiss)
            .accessibilityLabel(l10n.settingsPanes.dismissMessageA11y)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// One key of a keyboard shortcut drawn as a small key cap.
struct KeyCap: View {
    let key: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Text(key)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, key.count > 1 ? 9 : 0)
            .frame(minWidth: 28, minHeight: 28)
            .background {
                shape
                    .fill(.background)
                    .shadow(color: .black.opacity(0.14), radius: 0, y: 1.5)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
            }
    }
}

/// Type-erases the two glass button styles so a single button can switch between them.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

extension AnyPrimitiveButtonStyle {
    /// `.glassProminent` when selected, `.glass` otherwise.
    static func glass(selected: Bool) -> AnyPrimitiveButtonStyle {
        selected ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass)
    }
}

extension ScreenEdge {
    func title(_ l10n: Localizer) -> String {
        switch self {
        case .top: l10n.placement.top
        case .bottom: l10n.placement.bottom
        case .left: l10n.placement.left
        case .right: l10n.placement.right
        }
    }

    /// VoiceOver name of the button that moves the island to this edge.
    func moveA11y(_ l10n: Localizer) -> String {
        switch self {
        case .top: l10n.placement.moveToTopA11y
        case .bottom: l10n.placement.moveToBottomA11y
        case .left: l10n.placement.moveToLeftA11y
        case .right: l10n.placement.moveToRightA11y
        }
    }

    var systemImage: String {
        switch self {
        case .top: "rectangle.tophalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        }
    }
}

extension String {
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
