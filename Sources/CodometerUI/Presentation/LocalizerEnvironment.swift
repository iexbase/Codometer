import CodometerL10n
import SwiftUI

extension EnvironmentValues {
    /// The interface language and region for the views below.
    ///
    /// Every hosting root injects `.environment(\.l10n, store.localizer).environment(\.locale, store.localizer.locale)`,
    /// so our phrases and the system's live text (relative dates, formatted numbers) agree. Views read
    /// `@Environment(\.l10n) private var l10n` and pass `l10n.<area>.<phrase>` to SwiftUI, never literals.
    @Entry public var l10n = Localizer(language: .en)
}
