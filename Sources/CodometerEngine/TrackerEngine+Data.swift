import CodometerClaude
import CodometerCodex
import CodometerCore
import CodometerPlatform
import CodometerStorage
import Foundation
import os

/// Data controls: history export, erase, retention and the onboarding profile inspector.
extension TrackerEngine {
    /// Writes the history to `url` in the requested format (a JSON file or a folder of CSV files).
    ///
    /// Pending writes are stored first, so the export holds everything recorded so far. Rows are read in bounded
    /// pages and streamed into `<name>.partial`, which is renamed into place at the end; a failure or cancellation
    /// leaves nothing behind. Account identities (and so e-mails) are never exported.
    public func export(_ request: HistoryExportRequest, to url: URL) async throws(HistoryExportError) -> HistoryExportSummary {
        guard let history = dependencies.history else { throw .historyUnavailable }
        await recorder?.flush()
        let exporter = HistoryExporter(
            request: request,
            accounts: settings.accounts.map { profile in
                HistoryExporter.Account(
                    id: profile.id.description,
                    label: request.labels[profile.id],
                    provider: profile.provider.rawValue
                )
            },
            exportedAt: dependencies.now()
        )
        let summary = try await exporter.write(from: StoreExportSource(store: history), to: url)
        AppLog.storage.notice("exported \(summary.rowCount, privacy: .public) history rows")
        return summary
    }

    /// Before "Erase All Data": stops every monitor, ends the open collection runs and segments, writes everything
    /// pending and closes SQLite, so no file is written after this point. Later history calls fail with `.closed`.
    public func prepareForErase() async {
        await stop()
        await dependencies.history?.close()
        AppLog.storage.notice("history closed for erase")
    }

    /// Readiness of the profile folders onboarding offers, from filesystem metadata only (no CLI is started).
    ///
    /// Each row also carries the provider CLI's signature when the app has already looked at the binary
    /// (`ProfileReadiness.cli`). Nothing is inspected here: the first look at a CLI reads the whole binary to check
    /// its code signature and takes a second or two on a large one, and the wizard's list must not wait for that —
    /// while it waited, the step would say it found no profiles. `warmExecutableSignatures()` does that look off
    /// the readiness path.
    public func inspectProfiles() async -> [ProfileReadiness] {
        var signatures: [ProviderKind: ExecutableDiagnostics.Signature] = [:]
        signatures[.claude] = await dependencies.claudeProbe.lastSignature
        signatures[.codex] = await dependencies.codexProbe.lastSignature
        return profileInspector.inspect(
            homeDirectory: dependencies.homeDirectory,
            accounts: settings.accounts,
            signatures: signatures
        )
    }

    /// Looks each provider's CLI up once and remembers its signature, so the next `inspectProfiles()` can report it.
    ///
    /// Nothing is spawned, so this is allowed while onboarding is open: the binary is inspected and its
    /// signature verified, Claude's version step is told not to wait for the probe gate, and Codex reports the
    /// version its last handshake saw. A provider whose signature is already known is skipped, so calling this
    /// after every readiness read costs nothing once it has run.
    public func warmExecutableSignatures() async {
        if await dependencies.claudeProbe.lastSignature == nil {
            _ = await dependencies.claudeProbe.executableDiagnostics(readsVersion: false)
        }
        if await dependencies.codexProbe.lastSignature == nil {
            _ = await dependencies.codexProbe.executableDiagnostics()
        }
    }

    /// Called by `apply(settings:)` when the history retention changed: the store keeps less (or more) from now on,
    /// and anything already older than the new retention is pruned right away.
    func applyRetention(_ retention: HistoryRetention) {
        guard let recorder else { return }
        recorder.enqueue([.setRetention(retention.timeInterval), .prune(now: dependencies.now())])
    }
}
