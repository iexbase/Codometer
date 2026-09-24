import CodometerL10n
import SwiftUI

extension EnvironmentValues {
    /// The widget's language and region, set by `LimitsWidgetView` from the snapshot (`LimitsEntry.localizer`).
    ///
    /// Named apart from the app's `\.l10n`: this module does not import the UI module, and a test target that imports
    /// both must not see two entries with one name.
    @Entry public var widgetL10n = Localizer(language: .en)
}
