import CodometerWidgetsUI
import SwiftUI
import WidgetKit

/// Entry point of the widget extension (`CodometerWidgets.appex`). The process starts in `NSExtensionMain`,
/// which runs this bundle's `main`.
@main
struct CodometerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LimitsWidget()
        ClaudeLimitsWidget()
        CodexLimitsWidget()
        LimitsStripWidget()
        ClaudeStripWidget()
        CodexStripWidget()
    }
}
