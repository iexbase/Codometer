@testable import CodometerApp
import CodometerCore
import CodometerUI
import Foundation
import Testing

/// "Export Diagnostics…" now reads the pane's "Include account names" box, like "Copy Report" always did. The file
/// must still be the safe one by default: a caller that says nothing gets no account names.
@MainActor
@Suite("Diagnostics export")
struct DiagnosticsExportTests {
    private static let ranAt = Date(timeIntervalSince1970: 1_789_600_000)
    private static let account = AccountID()

    private static func report() -> SystemCheckReport {
        SystemCheckReport(
            ranAt: ranAt,
            items: [
                SystemCheckReport.Item(
                    id: "claudeProfile:\(account)",
                    status: .ok,
                    kind: .claudeProfile,
                    detail: "signed in as Night shift"
                ),
            ]
        )
    }

    private static let labels: [AccountID: String] = [account: "Night shift"]

    @Test("With the box on, the saved text carries the account label")
    func withNames() {
        let text = DiagnosticsExport.text(Self.report(), includeAccountNames: true, labels: Self.labels)
        #expect(text.contains("Night shift"))
        #expect(!text.contains(Self.account.description))
    }

    @Test("With the box off, the label is replaced by a number")
    func withoutNames() {
        let text = DiagnosticsExport.text(Self.report(), includeAccountNames: false, labels: Self.labels)
        #expect(!text.contains("Night shift"))
        #expect(text.contains("Account 1"))
        #expect(!text.contains(Self.account.description))
    }

    @Test("The default is the safe one")
    func defaultIsRedacted() {
        let byDefault = DiagnosticsExport.text(Self.report(), labels: Self.labels)
        #expect(byDefault == DiagnosticsExport.text(Self.report(), includeAccountNames: false, labels: Self.labels))
    }

    @Test("The action carries the box through to the app, and does nothing by default")
    func actionCarriesTheFlag() {
        let seen = Box()
        let actions = TrackerActions(
            refresh: { _ in },
            persistSettings: { _ in },
            discoverProfiles: { [] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: {},
            quit: {},
            exportDiagnostics: { seen.value = $0 }
        )
        actions.exportDiagnostics(true)
        #expect(seen.value == true)
        actions.exportDiagnostics(false)
        #expect(seen.value == false)

        // A caller that leaves the action out gets one that ignores the flag instead of a crash.
        let empty = TrackerActions(
            refresh: { _ in },
            persistSettings: { _ in },
            discoverProfiles: { [] },
            revealDataFolder: {},
            setLaunchAtLogin: { _ in nil },
            openSettings: {},
            quit: {}
        )
        empty.exportDiagnostics(true)
    }

    /// The file name never carries a name either.
    @Test("The file is named after the day only")
    func fileName() {
        #expect(DiagnosticsExport.fileName(for: Self.ranAt).hasPrefix("Codometer-diagnostics-"))
        #expect(DiagnosticsExport.fileName(for: Self.ranAt).hasSuffix(".txt"))
    }

    private final class Box {
        var value: Bool?
    }
}
