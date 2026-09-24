import CodometerCore
import CodometerL10n
import SwiftUI

/// The expanded card: header, hero ring, tiles and footer, for one account.
///
/// The card's size is fixed by `CardMetrics`, so nothing here can resize it; values only have to fit. Switching
/// accounts slides and crossfades the content inside that fixed frame.
struct CardFaceView: View {
    let store: TrackerStore
    let model: FloatingCardModel
    let accounts: [AccountPresentation]

    @Environment(\.l10n) private var l10n
    @Environment(\.cardTheme) private var theme
    @Environment(\.cardMetrics) private var metrics

    private var presentation: AccountPresentation? {
        accounts.first { $0.id == model.selectedAccountID } ?? accounts.first
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
            minimizeButton
        }
        .frame(width: model.cardFrame.width, height: model.cardFrame.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.card.cardA11y)
    }

    @ViewBuilder
    private var content: some View {
        if let presentation {
            let plan = CardContentPlan(
                presentation: presentation,
                settings: store.settings,
                thirdTile: model.thirdTile,
                serviceStatus: store.serviceStatus,
                ceremonies: store.ceremonies,
                now: store.now,
                l10n: l10n,
                // Only the strip plans over the scope; the other sizes never pay for it.
                stripScope: model.size == .strip ? model.stripScope : nil,
                scopePresentations: accounts
            )
            Group {
                switch model.size {
                case .regular: regular(presentation: presentation, plan: plan)
                case .compact: compact(presentation: presentation, plan: plan)
                case .strip: strip(presentation: presentation, plan: plan)
                }
            }
            // A merged strip keeps its content when the followed account changes: only its own scope moves it.
            .id(model.size == .strip && plan.strip?.header.isSelectedAccount == false ? nil : presentation.id)
            .transition(.asymmetric(
                insertion: .offset(x: 12).combined(with: .opacity),
                removal: .offset(x: -12).combined(with: .opacity)
            ))
            .animation(Motion.content, value: presentation.id)
        } else {
            emptyState
        }
    }

    // MARK: - Regular

    private func regular(presentation: AccountPresentation, plan: CardContentPlan) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            header(presentation: presentation, plan: plan, showsPillText: true)
            HStack(alignment: .center, spacing: metrics.tileSpacing) {
                hero(plan: plan)
                Spacer(minLength: metrics.tileSpacing)
                ring(presentation: presentation, diameter: metrics.heroRing(.regular))
            }
            .frame(width: metrics.innerWidth(.regular), alignment: .leading)
            CardTilesView(tiles: plan.tiles, size: .regular)
            footer(presentation: presentation, plan: plan)
        }
        .padding(metrics.padding)
        .frame(width: model.cardFrame.width, height: model.cardFrame.height, alignment: .top)
    }

    private func hero(plan: CardContentPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.hero?.caption ?? l10n.common.noData)
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(plan.hero?.figure ?? l10n.card.noValue)
                .font(metrics.font(.hero))
                .foregroundStyle(theme.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(plan.hero?.unit ?? l10n.card.used)
                .font(metrics.font(.heroUnit))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.hero?.accessibilityText ?? l10n.common.noData)
    }

    // MARK: - Compact

    private func compact(presentation: AccountPresentation, plan: CardContentPlan) -> some View {
        VStack(spacing: metrics.rowSpacing * 0.5) {
            header(presentation: presentation, plan: plan, showsPillText: false)
            Spacer(minLength: 0)
            ring(presentation: presentation, diameter: metrics.heroRing(.compact))
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(plan.hero?.figure ?? l10n.card.noValue)
                        .font(metrics.font(.tileValue))
                        .foregroundStyle(theme.primaryTextColor)
                        .contentTransition(.numericText())
                    Text(plan.hero?.unit ?? l10n.card.used)
                        .font(metrics.font(.heroUnit))
                        .foregroundStyle(theme.secondaryTextColor)
                }
                Text(compactCaption(plan: plan))
                    .font(metrics.font(.footer))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plan.hero?.accessibilityText ?? l10n.common.noData)
            CardPageDots(
                accounts: accounts,
                selected: presentation.id,
                isPinned: model.isAccountPinned,
                onSelect: { model.send(.selectAccount($0)) }
            )
            .frame(width: metrics.innerWidth(.compact))
        }
        .padding(metrics.padding)
        .frame(width: model.cardFrame.width, height: model.cardFrame.height)
    }

    /// "Weekly · All models · 5d 16h": the hero window and its reset in one line.
    private func compactCaption(plan: CardContentPlan) -> String {
        let reset = plan.tiles.first { $0.kind == .reset }?.value
        return [plan.hero?.caption, reset].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Strip

    private func strip(presentation: AccountPresentation, plan: CardContentPlan) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            stripHeader(presentation: presentation, plan: plan)
            if let strip = plan.strip {
                CardStripBody(plan: strip)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(metrics.padding)
        .frame(width: model.cardFrame.width, height: model.cardFrame.height, alignment: .top)
    }

    /// The strip's header: the account chip (or the scope's name), the page dots, when the data arrived, and the
    /// status pill — all on one line, because the strip has the width for it and no footer.
    private func stripHeader(presentation: AccountPresentation, plan: CardContentPlan) -> some View {
        HStack(spacing: 6) {
            if let strip = plan.strip, !strip.header.isSelectedAccount {
                CardScopeChip(header: strip.header)
            } else {
                CardAccountChip(
                    style: presentation.style,
                    provider: presentation.provider,
                    label: plan.accountLabel,
                    plan: plan.plan,
                    hasMenu: accounts.count > 1,
                    onOpenMenu: { model.send(.accountMenu) }
                )
                CardPageDots(
                    accounts: accounts,
                    selected: presentation.id,
                    isPinned: model.isAccountPinned,
                    onSelect: { model.send(.selectAccount($0)) }
                )
            }
            Spacer(minLength: 4)
            Text(plan.updated)
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .layoutPriority(-1)
            CardStatusPill(pill: plan.pill, showsText: true) { provider in
                model.send(.openStatusPage(provider))
            }
        }
        .padding(.trailing, metrics.minimizeButton * 0.9)
        .frame(width: metrics.innerWidth(.strip), height: metrics.headerHeight, alignment: .leading)
    }

    // MARK: - Pieces

    private func header(presentation: AccountPresentation, plan: CardContentPlan, showsPillText: Bool) -> some View {
        HStack(spacing: 6) {
            CardAccountChip(
                style: presentation.style,
                provider: presentation.provider,
                label: plan.accountLabel,
                plan: showsPillText ? plan.plan : nil,
                hasMenu: accounts.count > 1,
                onOpenMenu: { model.send(.accountMenu) }
            )
            Spacer(minLength: 4)
            CardStatusPill(pill: plan.pill, showsText: showsPillText) { provider in
                model.send(.openStatusPage(provider))
            }
        }
        // The minimize button lives in the same corner: keep the header clear of it.
        .padding(.trailing, metrics.minimizeButton * 0.9)
        .frame(width: metrics.innerWidth(model.size), alignment: .leading)
    }

    private func ring(presentation: AccountPresentation, diameter: CGFloat) -> some View {
        RingGauge(
            presentation: presentation,
            diameter: diameter,
            showsSecondary: store.settings.appearance.showsSecondaryRing,
            forecastPolicy: .always,
            ceremonySurface: .card
        )
        // The hero next to it already speaks the account's usage and its forecast; a second, differently worded
        // reading of the same rings would only make the card longer to listen to.
        .accessibilityHidden(true)
    }

    private func footer(presentation: AccountPresentation, plan: CardContentPlan) -> some View {
        let dots = CardPageDots(
            accounts: accounts,
            selected: presentation.id,
            isPinned: model.isAccountPinned,
            onSelect: { model.send(.selectAccount($0)) }
        )
        return HStack(spacing: 4) {
            Text("\(plan.identity) · \(plan.updated)")
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            // The dots keep their room; a long identity truncates instead.
            dots.layoutPriority(1)
        }
        .frame(width: metrics.innerWidth(model.size), height: metrics.minimizeButton, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(l10n.emptyState.noAccountsTitle)
                .font(metrics.font(.header))
                .foregroundStyle(theme.primaryTextColor)
            Text(l10n.emptyState.noAccountsBody)
                .font(metrics.font(.footer))
                .foregroundStyle(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(metrics.padding)
        .frame(width: model.cardFrame.width, height: model.cardFrame.height)
    }

    private var minimizeButton: some View {
        Button {
            model.send(.minimize)
        } label: {
            Image(systemName: "minus")
                .font(metrics.font(TextSize.badge, .semibold))
                .foregroundStyle(theme.secondaryTextColor)
                .frame(width: metrics.minimizeButton, height: metrics.minimizeButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(metrics.padding * 0.4)
        // Quiet until the pointer is on the card, but always there for VoiceOver and for keyboard users.
        .opacity(model.isHovered || model.isKeyboardEngaged ? 1 : 0)
        .animation(Motion.quickFade, value: model.isHovered)
        .help(l10n.card.minimize)
        .accessibilityLabel(l10n.card.minimize)
    }
}
