import Foundation

/// One account's refresh history and state, gathered on demand for the Diagnostics pane (never persisted).
public struct AccountDiagnostics: Hashable, Sendable {
    public static let maximumProbes = 16

    public let accountID: AccountID
    public let provider: ProviderKind
    /// Newest first, at most 16.
    public let recentProbes: [ProbeRecord]
    /// The latest reading derived from Codex session logs.
    public let lastLogReadingAt: Date?
    public let nextRefreshAt: Date?
    public let consecutiveFailures: Int
    /// The energy factor applied to this account's schedule, within `EnergyFactor.allowed`.
    public let energyFactor: Double
    public let drift: FormatDrift

    public init(
        accountID: AccountID,
        provider: ProviderKind,
        recentProbes: [ProbeRecord],
        lastLogReadingAt: Date?,
        nextRefreshAt: Date?,
        consecutiveFailures: Int,
        energyFactor: Double,
        drift: FormatDrift
    ) {
        self.accountID = accountID
        self.provider = provider
        self.recentProbes = Array(recentProbes.sorted { $0.startedAt > $1.startedAt }.prefix(Self.maximumProbes))
        self.lastLogReadingAt = lastLogReadingAt
        self.nextRefreshAt = nextRefreshAt
        self.consecutiveFailures = max(0, consecutiveFailures)
        let allowed = EnergyFactor.allowed
        self.energyFactor = energyFactor.isFinite ? min(max(energyFactor, allowed.lowerBound), allowed.upperBound) : 1
        self.drift = drift
    }

    /// An account that has not refreshed yet.
    public static func empty(accountID: AccountID, provider: ProviderKind) -> AccountDiagnostics {
        AccountDiagnostics(
            accountID: accountID,
            provider: provider,
            recentProbes: [],
            lastLogReadingAt: nil,
            nextRefreshAt: nil,
            consecutiveFailures: 0,
            energyFactor: 1,
            drift: .empty
        )
    }
}

/// Everything the engine reports to the Diagnostics pane in one pull.
public struct EngineDiagnostics: Hashable, Sendable {
    public let generatedAt: Date
    public let accounts: [AccountDiagnostics]
    public let executables: [ProviderKind: ExecutableDiagnostics]
    public let history: HistoryDiagnostics
    public let energy: EnergyDecision
    /// The power conditions behind `energy`, when known.
    public let power: PowerSnapshot?

    public init(
        generatedAt: Date,
        accounts: [AccountDiagnostics],
        executables: [ProviderKind: ExecutableDiagnostics],
        history: HistoryDiagnostics,
        energy: EnergyDecision,
        power: PowerSnapshot?
    ) {
        self.generatedAt = generatedAt
        self.accounts = accounts
        self.executables = executables
        self.history = history
        self.energy = energy
        self.power = power
    }
}
