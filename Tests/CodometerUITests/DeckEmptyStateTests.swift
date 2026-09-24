import CodometerCore
import CodometerL10n
@testable import CodometerUI
import AppKit
import Foundation
import SwiftUI
import Testing

@Suite("Deck empty states")
@MainActor
struct DeckEmptyStateTests {
    @Test("A group with accounts shows dials, the page switcher and pages")
    func accountsShown() throws {
        let work = try UIFixture.group("Работа")
        let sections = DeckSections.make(accountCount: 3, shownCount: 2, configuredAccountCount: 3, enabledInSettingsCount: 3, filter: work.id, groups: [work], attentionCount: 0, pageCount: 2)
        #expect(sections.groupFilter == .shown)
        #expect(sections.attention == .absent)
        #expect(sections.dials == .shown)
        #expect(sections.pageSwitcher == .shown)
        #expect(sections.pages == .shown)
        #expect(sections.emptyState == nil)

        let ungrouped = DeckSections.make(accountCount: 1, shownCount: 1, configuredAccountCount: 1, enabledInSettingsCount: 1, filter: nil, groups: [], attentionCount: 2, pageCount: 1)
        #expect(ungrouped.groupFilter == .absent)
        #expect(ungrouped.attention == .shown)
        // One page needs no switcher.
        #expect(ungrouped.pageSwitcher == .absent)
        #expect(ungrouped.pages == .shown)
    }

    @Test("An empty group reserves the account room under its empty state and keeps the filter")
    func emptyGroup() throws {
        let work = try UIFixture.group("Работа")
        let folder = try UIFixture.group("Folder 1")
        let sections = DeckSections.make(accountCount: 2, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 2, filter: folder.id, groups: [work, folder], attentionCount: 0, pageCount: 2)
        // The user can switch back from the header.
        #expect(sections.groupFilter == .shown)
        #expect(sections.attention == .absent)
        // Nothing of the accounts is visible, but everything keeps its room.
        #expect(sections.dials == .reserved)
        #expect(sections.pageSwitcher == .reserved)
        #expect(sections.pages == .reserved)
        #expect(!sections.dials.isShown && !sections.pageSwitcher.isShown && !sections.pages.isShown)
        #expect(sections.dials.isLaidOut && sections.pageSwitcher.isLaidOut && sections.pages.isLaidOut)
        #expect(sections.emptyState == .group(name: "Folder 1"))

        // "Waiting for you" covers every group, and the rail's attention tab opens the deck on it.
        let waiting = DeckSections.make(accountCount: 2, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 2, filter: folder.id, groups: [work, folder], attentionCount: 1, pageCount: 2)
        #expect(waiting.attention == .shown)
        #expect(waiting.pageSwitcher == .reserved)

        let singlePage = DeckSections.make(accountCount: 2, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 2, filter: folder.id, groups: [work, folder], attentionCount: 0, pageCount: 1)
        #expect(singlePage.pageSwitcher == .absent)
        #expect(singlePage.pages == .reserved)

        let unknown = DeckSections.make(accountCount: 2, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 2, filter: AccountGroupID(), groups: [work], attentionCount: 0, pageCount: 2)
        #expect(unknown.emptyState == .group(name: nil))
    }

    @Test("Without accounts the deck is the header and the empty state")
    func noAccounts() throws {
        let work = try UIFixture.group("Работа")
        let none = DeckSections.make(accountCount: 0, shownCount: 0, configuredAccountCount: 0, enabledInSettingsCount: 0, filter: nil, groups: [], attentionCount: 0, pageCount: 2)
        #expect(none.groupFilter == .absent)
        #expect(none.attention == .absent)
        #expect(none.dials == .absent)
        #expect(none.pageSwitcher == .absent)
        #expect(none.pages == .absent)
        #expect(none.emptyState == .noAccounts)

        // Even with a group filter on, no accounts at all is the more useful thing to say.
        let filtered = DeckSections.make(accountCount: 0, shownCount: 0, configuredAccountCount: 0, enabledInSettingsCount: 0, filter: work.id, groups: [work], attentionCount: 0, pageCount: 2)
        #expect(filtered.groupFilter == .shown)
        #expect(filtered.pageSwitcher == .absent)
        #expect(filtered.emptyState == .noAccounts)

        let disabled = DeckSections.make(accountCount: 0, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 0, filter: nil, groups: [], attentionCount: 0, pageCount: 2)
        #expect(disabled.emptyState == .allDisabled)
        #expect(disabled.pages == .absent)
    }

    @Test("Enabled accounts the engine has not published yet are loading, not turned off")
    func loading() throws {
        let work = try UIFixture.group("Работа")
        // At launch the store starts with an empty state while settings already list enabled accounts.
        let launch = DeckSections.make(accountCount: 0, shownCount: 0, configuredAccountCount: 2, enabledInSettingsCount: 1, filter: nil, groups: [], attentionCount: 0, pageCount: 2)
        #expect(launch.emptyState == .loading)
        #expect(launch.dials == .absent && launch.pageSwitcher == .absent && launch.pages == .absent)
        let filtered = DeckSections.make(accountCount: 0, shownCount: 0, configuredAccountCount: 1, enabledInSettingsCount: 1, filter: work.id, groups: [work], attentionCount: 0, pageCount: 2)
        #expect(filtered.emptyState == .loading)
        #expect(filtered.groupFilter == .shown)

        let state = DeckSections.EmptyState.loading
        #expect(state.title(l10n: .testRussian) == "Загрузка аккаунтов…")
        #expect(state.headerSubtitle(l10n: .testRussian) == "ожидание данных")
        #expect(state.title(l10n: .testEnglish) == "Loading accounts…")
        #expect(state.message(l10n: .testEnglish) == "Your limits will appear in a few seconds.")
        #expect(state.headerSubtitle(l10n: .testEnglish) == "Waiting for data")
        // Nothing to fix while loading.
        #expect(!state.offersShowAll)
        #expect(!state.offersSettings)
    }

    @Test("Sections from a store: launch, switched off, published")
    func sectionsFromStore() throws {
        let profile = try UIFixture.profile("Claude")
        let store = TrackerStore(state: .empty, settings: try AppSettings(accounts: [profile], groups: []), now: UIFixture.now, actions: UIFixture.actions())
        func sections() -> DeckSections {
            DeckSections.make(accountCount: store.presentations.count, shownCount: store.presentations.count, settings: store.settings, attentionCount: 0, pageCount: 2)
        }
        // At launch the store has no engine state yet.
        #expect(sections().emptyState == .loading)
        store.receive(TrackerState(accounts: [AccountStatus(profile: profile)]))
        #expect(sections().emptyState == nil)
        #expect(sections().pages == .shown)

        let off = try UIFixture.profile("Claude", isEnabled: false)
        _ = store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in settings = try settings.replacingAccounts([off]) }
        store.receive(TrackerState(accounts: [AccountStatus(profile: off)]))
        #expect(sections().emptyState == .allDisabled)

        _ = store.updateSettings { (settings: inout AppSettings) throws(ValidationError) in settings = try settings.replacingAccounts([]) }
        #expect(sections().emptyState == .noAccounts)
    }

    @Test("Content sits at the room's optical centre", arguments: [
        (room: 600.0, content: 200.0, fraction: 0.4, expected: 160.0),
        (room: 600.0, content: 200.0, fraction: 0.5, expected: 200.0),
        (room: 201.0, content: 200.0, fraction: 0.4, expected: 0.0),
        (room: 150.0, content: 200.0, fraction: 0.4, expected: 0.0),
        (room: 600.0, content: 200.0, fraction: 2.0, expected: 400.0),
        (room: 600.0, content: 200.0, fraction: -1.0, expected: 0.0),
        (room: .infinity, content: 200.0, fraction: 0.4, expected: 0.0),
    ])
    func opticalCenter(room: CGFloat, content: CGFloat, fraction: CGFloat, expected: CGFloat) {
        #expect(OpticalCenterLayout.offset(room: room, content: content, fraction: fraction) == expected)
        // Above the middle, never below it.
        #expect(OpticalCenterLayout.defaultFraction < 0.5)
    }

    @Test("The empty state fits the smallest room an empty group keeps, in both languages", arguments: [0.85, 1.0, 1.3], [Localizer.testEnglish, .testRussian])
    func emptyStateFitsRoom(scale: CGFloat, l10n: Localizer) throws {
        // One account without any reading or session keeps the least room.
        let work = try UIFixture.group("Работа")
        let empty = try UIFixture.group("Очень длинное имя группы")
        let profile = try UIFixture.profile("Claude", group: work)
        var settings = try AppSettings(accounts: [profile], groups: [work, empty])
        settings.appearance.railGroupFilter = empty.id
        let store = TrackerStore(state: TrackerState(accounts: [AccountStatus(profile: profile)]), settings: settings, now: UIFixture.now, actions: UIFixture.actions())
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: scale)))
        let metrics = model.layout.metrics
        let inner = metrics.deckWidth - metrics.deckPadding * 2

        let deck = measure(store: store, model: model, context: .island, l10n: l10n)
        let header = NSHostingView(rootView: DeckHeader(store: store, accounts: store.presentations, context: .island, metrics: metrics)
            .frame(width: inner)
            .fixedSize()
            .environment(\.l10n, l10n)).fittingSize
        for state in [DeckSections.EmptyState.group(name: empty.name.value), .group(name: nil)] {
            let size = NSHostingView(rootView: DeckEmptyStateView(state: state, metrics: metrics, fillsRoom: false, onShowAll: {}, onOpenSettings: {})
                .frame(width: inner)
                .fixedSize()
                .environment(\.l10n, l10n)).fittingSize
            let room = deck.height - metrics.deckVerticalPadding * 2 - header.height - metrics.sectionSpacing
            #expect(size.height > 0)
            #expect(size.height <= room, "\(l10n.language) scale \(scale): empty state \(size.height) pt, room \(room) pt")
        }
    }

    @Test("Empty state texts and actions")
    func texts() {
        let ru = Localizer.testRussian
        let group = DeckSections.EmptyState.group(name: "Folder 1")
        #expect(group.title(l10n: ru) == "В группе «Folder 1» нет аккаунтов")
        #expect(DeckSections.EmptyState.group(name: nil).title(l10n: ru) == "В этой группе нет аккаунтов")
        #expect(group.message(l10n: ru) == "Добавьте в неё аккаунт в настройках или покажите все группы.")
        #expect(group.offersShowAll)
        #expect(group.headerSubtitle(l10n: ru) == nil)

        #expect(DeckSections.EmptyState.noAccounts.title(l10n: ru) == "Аккаунтов пока нет")
        #expect(DeckSections.EmptyState.noAccounts.message(l10n: ru) == "Добавьте профиль Claude Code или Codex в настройках.")
        #expect(!DeckSections.EmptyState.noAccounts.offersShowAll)
        #expect(DeckSections.EmptyState.noAccounts.headerSubtitle(l10n: ru) == "пока не настроены")
        #expect(DeckSections.EmptyState.allDisabled.title(l10n: ru) == "Все аккаунты выключены")
        #expect(!DeckSections.EmptyState.allDisabled.offersShowAll)
        #expect(DeckSections.EmptyState.allDisabled.headerSubtitle(l10n: ru) == "отслеживание приостановлено")
        #expect(group.offersSettings && DeckSections.EmptyState.noAccounts.offersSettings && DeckSections.EmptyState.allDisabled.offersSettings)
        for l10n in [Localizer.testEnglish, ru] {
            for state in [group, .group(name: nil), .noAccounts, .allDisabled, .loading] {
                #expect(!state.title(l10n: l10n).isEmpty)
                // One paragraph that wraps in the deck's width: no hand-made line breaks.
                #expect(!state.message(l10n: l10n).isEmpty)
                #expect(!state.message(l10n: l10n).contains("\n"))
                #expect(NSImage(systemSymbolName: state.systemImage, accessibilityDescription: nil) != nil)
            }
        }
    }

    @Test("Empty state copy in English")
    func englishTexts() {
        let en = Localizer.testEnglish
        #expect(DeckSections.EmptyState.group(name: "Work").title(l10n: en) == "No accounts in “Work”")
        #expect(DeckSections.EmptyState.group(name: nil).title(l10n: en) == "No accounts in this group")
        #expect(DeckSections.EmptyState.group(name: "Work").message(l10n: en) == "Add an account to this group in Settings, or show all groups.")
        #expect(DeckSections.EmptyState.noAccounts.title(l10n: en) == "No accounts yet")
        #expect(DeckSections.EmptyState.noAccounts.message(l10n: en) == "Add a Claude Code or Codex profile in Settings.")
        #expect(DeckSections.EmptyState.noAccounts.headerSubtitle(l10n: en) == "Not set up yet")
        #expect(DeckSections.EmptyState.allDisabled.title(l10n: en) == "All accounts are turned off")
        #expect(DeckSections.EmptyState.allDisabled.message(l10n: en) == "Turn on an account in Settings to see its limits.")
        #expect(DeckSections.EmptyState.allDisabled.headerSubtitle(l10n: en) == "Tracking paused")
        #expect(en.emptyState.showAll == "Show All")
        #expect(en.emptyState.openSettings == "Open Settings")
        #expect(Localizer.testRussian.emptyState.showAll == "Показать все")
        #expect(Localizer.testRussian.emptyState.openSettings == "Открыть настройки")
    }

    @Test("The measured deck keeps one size across group switches, in both languages", arguments: [false, true], [Localizer.testEnglish, .testRussian])
    func stableSizeAcrossGroups(waiting: Bool, l10n: Localizer) throws {
        let fixture = try DeckEmptyStateFixture(waiting: waiting)
        let store = fixture.store
        for context in [DeckContext.island, .popover] {
            for (edge, style, scale) in [(ScreenEdge.top, IslandStyle.floating, 1.0), (.top, .attached, 1.0), (.right, .floating, 0.85)] {
                let model = IslandModel(layout: IslandLayout(edge: edge, anchor: edge == .top ? .top : .trailing, style: style, metrics: IslandMetrics(scale: scale)))
                var sizes: [String: CGSize] = [:]
                for (name, filter) in [("all", nil), ("work", fixture.work.id), ("personal", fixture.personal.id), ("empty", fixture.empty.id), ("all again", nil)] as [(String, AccountGroupID?)] {
                    store.updateSettings { $0.appearance.railGroupFilter = filter }
                    #expect(store.settings.appearance.railGroupFilter == filter)
                    sizes[name] = measure(store: store, model: model, context: context, l10n: l10n)
                }
                let reference = try #require(sizes["all"])
                #expect(reference.height > 200)
                for (name, size) in sizes {
                    #expect(size == reference, "\(l10n.language) \(context) \(edge) \(style) \(scale): “\(name)” measured \(size), “all” \(reference)")
                }
            }
        }
    }

    @Test("The same deck view keeps its size while the filter changes under it")
    func stableSizeInPlace() throws {
        let fixture = try DeckEmptyStateFixture(waiting: false)
        let store = fixture.store
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        let view = NSHostingView(rootView: deck(store: store, model: model, context: .island))
        view.layoutSubtreeIfNeeded()
        let initial = view.fittingSize
        for filter in [fixture.empty.id, fixture.work.id, fixture.empty.id, nil] as [AccountGroupID?] {
            store.updateSettings { $0.appearance.railGroupFilter = filter }
            view.layoutSubtreeIfNeeded()
            #expect(view.fittingSize == initial)
        }
    }

    @Test("No accounts: a compact deck, header and empty state only")
    func compactWithoutAccounts() throws {
        let fixture = try DeckEmptyStateFixture(waiting: false)
        let empty = DeckEmptyStateFixture.emptyStore(groups: [fixture.work])
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        // The full account page (chart, sessions, footer) is the tall deck the compact one is measured against.
        fixture.store.updateSettings { $0.appearance.deckDetail = .full }
        let full = measure(store: fixture.store, model: model, context: .island)
        let compact = measure(store: empty, model: model, context: .island)
        #expect(compact.width == full.width)
        #expect(compact.height < full.height / 2)
    }

    private func deck(store: TrackerStore, model: IslandModel, context: DeckContext, l10n: Localizer = .testEnglish) -> some View {
        DeckContent(store: store, model: model, accounts: store.presentations, context: context)
            .fixedSize()
            .environment(\.liveEffectsEnabled, false)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
    }

    private func measure(store: TrackerStore, model: IslandModel, context: DeckContext, l10n: Localizer = .testEnglish) -> CGSize {
        let view = NSHostingView(rootView: deck(store: store, model: model, context: context, l10n: l10n))
        return view.fittingSize
    }
}

/// Renders the empty-group, no-account and normal decks to PNG for visual review, in English and Russian.
/// Runs only when `CODOMETER_SNAPSHOT_DIR` is set; files land in its `deck-empty` folder as `…-en.png` and `…-ru.png`.
@MainActor
@Suite("Deck empty state renders", .enabled(if: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] != nil))
struct DeckEmptyStateRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODOMETER_SNAPSHOT_DIR"] ?? "/tmp", isDirectory: true)
        .appendingPathComponent("deck-empty", isDirectory: true)

    @Test("Empty group, no accounts and the normal deck in light and dark, in both languages", arguments: [Localizer.testEnglish, .testRussian])
    func render(l10n: Localizer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let language = l10n.language.rawValue
        let fixture = try DeckEmptyStateFixture(waiting: false, l10n: l10n)
        let waitingFixture = try DeckEmptyStateFixture(waiting: true, l10n: l10n)
        let store = fixture.store
        let l10n = store.localizer
        let model = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .floating, metrics: IslandMetrics(scale: 1)))
        for scheme in [ColorScheme.light, .dark] {
            let suffix = "\(scheme == .dark ? "dark" : "light")-\(language)"
            store.updateSettings { $0.appearance.railGroupFilter = nil }
            try render(island(store: store, model: model), name: "deck-all-\(suffix)", scheme: scheme, l10n: l10n)
            store.updateSettings { $0.appearance.railGroupFilter = fixture.empty.id }
            try render(island(store: store, model: model), name: "deck-empty-group-\(suffix)", scheme: scheme, l10n: l10n)
            try render(
                // The popover injects the store's language itself, so render it through a store in that language.
                StatusPopoverView(store: store, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)),
                name: "popover-empty-group-\(suffix)",
                scheme: scheme,
                l10n: l10n
            )
            waitingFixture.store.updateSettings { $0.appearance.railGroupFilter = waitingFixture.empty.id }
            try render(island(store: waitingFixture.store, model: model), name: "deck-empty-group-waiting-\(suffix)", scheme: scheme, l10n: l10n)
            try render(island(store: DeckEmptyStateFixture.emptyStore(groups: [], l10n: l10n), model: model), name: "deck-no-accounts-\(suffix)", scheme: scheme, l10n: l10n)
            try render(island(store: DeckEmptyStateFixture.disabledStore(l10n: l10n), model: model), name: "deck-all-disabled-\(suffix)", scheme: scheme, l10n: l10n)
            try render(island(store: DeckEmptyStateFixture.loadingStore(l10n: l10n), model: model), name: "deck-loading-\(suffix)", scheme: scheme, l10n: l10n)
        }
        let attached = IslandModel(layout: IslandLayout(edge: .top, anchor: .top, style: .attached, metrics: IslandMetrics(scale: 1)))
        store.updateSettings { $0.appearance.railGroupFilter = fixture.empty.id }
        try render(
            DeckContent(store: store, model: attached, accounts: store.presentations, context: .island)
                .background(IslandRootView.silhouette(layout: attached.layout, expanded: true).fill(Color.black.opacity(0.72)))
                .environment(\.colorScheme, .dark),
            name: "deck-empty-group-attached-dark-\(language)",
            scheme: .dark,
            l10n: l10n
        )
    }

    private func island(store: TrackerStore, model: IslandModel) -> some View {
        DeckContent(store: store, model: model, accounts: store.presentations, context: .island)
            .background(RoundedRectangle(cornerRadius: model.layout.metrics.deckCorner, style: .continuous).fill(.regularMaterial))
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme, l10n: Localizer) throws {
        let content = view
            .padding(36)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.55, blue: 0.40), Color(red: 0.55, green: 0.33, blue: 0.86), Color(red: 0.16, green: 0.50, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, scheme)
            .environment(\.introAnimationsEnabled, false)
            .environment(\.liveEffectsEnabled, false)
            .environment(\.rendersGlass, false)
            .environment(\.l10n, l10n)
            .environment(\.locale, l10n.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

/// Three accounts in “Работа” and “Личное” (user data, never translated), and an empty “Folder 1”.
@MainActor
struct DeckEmptyStateFixture {
    let work: AccountGroup
    let personal: AccountGroup
    let empty: AccountGroup
    let store: TrackerStore

    /// - Parameter l10n: The language the store shows, with that language's own region; `nil` keeps the defaults.
    init(waiting: Bool, l10n: Localizer? = nil) throws {
        work = try UIFixture.group("Работа")
        personal = try UIFixture.group("Личное")
        empty = try UIFixture.group("Folder 1")
        let claude = try UIFixture.profile("Claude", group: work)
        let codex = try UIFixture.profile("Codex", provider: .codex, group: work)
        let spare = try UIFixture.profile("Claude 2", group: personal)
        let settings = try AppSettings(accounts: [claude, codex, spare], groups: [work, personal, empty])

        let claudeReading = try UIFixture.reading([
            try UIFixture.bucket("claude", [
                try UIFixture.window("session", .session, used: 42, duration: .fiveHours, resetsIn: 2 * 3_600),
                try UIFixture.window("week", .weekly(model: nil), used: 61, duration: .oneWeek, resetsIn: 3 * 86_400),
            ]),
        ], capturedAgo: 90)
        let codexReading = try UIFixture.reading([
            try UIFixture.bucket("codex", [
                try UIFixture.window("primary", used: 18, duration: .fiveHours, resetsIn: 4 * 3_600),
                try UIFixture.window("secondary", used: 33, duration: .oneWeek, resetsIn: 5 * 86_400),
            ]),
        ], capturedAgo: 40)
        let spareReading = try UIFixture.reading([
            try UIFixture.bucket("claude", [try UIFixture.window("session", .session, used: 7, duration: .fiveHours, resetsIn: 4 * 3_600)]),
        ], capturedAgo: 200)
        let sessions = try [
            UIFixture.session("Codometer", .working, since: 420),
        ] + (waiting ? [try AgentSession(
            id: "exchanger-api",
            title: "exchanger-api",
            projectPath: "/Users/me/api",
            activity: .waiting,
            detail: "permission prompt",
            activitySince: UIFixture.now.addingTimeInterval(-65),
            processID: nil
        )] : [])
        let state = TrackerState(accounts: [
            AccountStatus(profile: claude, reading: claudeReading, nextRefreshAt: UIFixture.now.addingTimeInterval(180), sessions: sessions),
            AccountStatus(profile: codex, reading: codexReading, nextRefreshAt: UIFixture.now.addingTimeInterval(150)),
            AccountStatus(profile: spare, reading: spareReading, nextRefreshAt: UIFixture.now.addingTimeInterval(240)),
        ])
        store = Self.store(state: state, settings: settings, l10n: l10n)
    }

    /// A store without accounts, optionally with groups (and a filter on the first one).
    static func emptyStore(groups: [AccountGroup], l10n: Localizer? = nil) -> TrackerStore {
        var settings = (try? AppSettings(accounts: [], groups: groups)) ?? .empty
        settings.appearance.railGroupFilter = groups.first?.id
        return store(state: TrackerState(accounts: []), settings: settings, l10n: l10n)
    }

    /// A store at launch: an enabled account in settings, no engine state yet.
    static func loadingStore(l10n: Localizer? = nil) throws -> TrackerStore {
        let settings = try AppSettings(accounts: [try UIFixture.profile("Claude")], groups: [])
        return store(state: .empty, settings: settings, l10n: l10n)
    }

    /// A store whose only account is switched off.
    static func disabledStore(l10n: Localizer? = nil) throws -> TrackerStore {
        let profile = try UIFixture.profile("Claude", isEnabled: false)
        let settings = try AppSettings(accounts: [profile], groups: [])
        let state = TrackerState(accounts: [AccountStatus(profile: profile)])
        return store(state: state, settings: settings, l10n: l10n)
    }

    /// A store in `l10n`'s language and a region that speaks it (en_US, ru_RU), or with the defaults.
    private static func store(state: TrackerState, settings: AppSettings, l10n: Localizer?) -> TrackerStore {
        guard let l10n else {
            return TrackerStore(state: state, settings: settings, now: UIFixture.now, actions: UIFixture.actions())
        }
        var settings = settings
        settings.general.language = l10n.language == .en ? .english : .russian
        let region = Locale(identifier: l10n.language == .en ? "en_US" : "ru_RU")
        return TrackerStore(
            state: state,
            settings: settings,
            now: UIFixture.now,
            actions: UIFixture.actions(),
            preferredLanguages: { ["en-US"] },
            region: { region }
        )
    }
}
