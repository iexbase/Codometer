import CodometerL10n
import SwiftUI

/// "Erase All Data…": what goes, what stays, and two ways to go through with it.
///
/// Two steps on purpose: the first lists the consequences and offers to export the history first, the second
/// asks once more and carries the destructive buttons. Escape cancels on either step. The sheet keeps one size, so
/// stepping forward never resizes it.
struct EraseDataSheet: View {
    /// Closes the sheet and opens the export save panel.
    let exportFirst: () -> Void
    /// `true` starts over (erase, relaunch into the welcome flow), `false` erases and quits.
    let erase: (Bool) -> Void
    let cancel: () -> Void

    /// The sheet's fixed size, wide enough for the Russian item lists without wrapping oddly.
    static let width: CGFloat = 520
    static let contentHeight: CGFloat = 320

    @State private var step: Step
    @Environment(\.l10n) private var l10n

    enum Step: Int, Hashable, CaseIterable {
        case review
        case confirm

        static let total = 2
        var number: Int { rawValue + 1 }
    }

    /// `initialStep` exists so renders can show the second step; the sheet always opens on the first one.
    init(
        initialStep: Step = .review,
        exportFirst: @escaping () -> Void,
        erase: @escaping (Bool) -> Void,
        cancel: @escaping () -> Void
    ) {
        _step = State(initialValue: initialStep)
        self.exportFirst = exportFirst
        self.erase = erase
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(22)
        .frame(width: Self.width)
        .frame(height: Self.contentHeight, alignment: .top)
        .background(.background)
        .onExitCommand(perform: cancel)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white, Color.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(step == .review ? l10n.dataControls.eraseSheetTitle : l10n.dataControls.eraseConfirmTitle)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(step == .review ? l10n.dataControls.eraseSheetIntro : l10n.dataControls.eraseConfirmBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(l10n.dataControls.eraseStepA11y(step.number, of: Step.total))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .review:
            HStack(alignment: .top, spacing: 26) {
                itemList(
                    title: l10n.dataControls.eraseRemovedTitle,
                    symbol: "minus.circle.fill",
                    tint: .red,
                    items: [
                        l10n.dataControls.eraseRemovedHistory,
                        l10n.dataControls.eraseRemovedSettings,
                        l10n.dataControls.eraseRemovedWidget,
                        l10n.dataControls.eraseRemovedNotifications,
                    ]
                )
                itemList(
                    title: l10n.dataControls.eraseKeptTitle,
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    items: [
                        l10n.dataControls.eraseKeptProfiles,
                        l10n.dataControls.eraseKeptExports,
                        l10n.dataControls.eraseKeptApp,
                    ]
                )
            }
        case .confirm:
            VStack(alignment: .leading, spacing: 12) {
                Button(l10n.dataControls.eraseAndQuit, role: .destructive) { erase(false) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                Button(l10n.dataControls.eraseAndStartOver, role: .destructive) { erase(true) }
                    .buttonStyle(.glass)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func itemList(title: String, symbol: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if step == .review {
                Button(l10n.dataControls.eraseExportFirst, action: exportFirst)
                    .buttonStyle(.glass)
            } else {
                Button(l10n.dataControls.eraseBack) { step = .review }
                    .buttonStyle(.glass)
            }
            Spacer(minLength: 0)
            Button(l10n.common.cancel, role: .cancel, action: cancel)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            if step == .review {
                Button(l10n.dataControls.eraseContinue, role: .destructive) { step = .confirm }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
