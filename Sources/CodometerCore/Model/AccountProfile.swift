import Foundation

public struct AccountID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

extension AccountID: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try UUID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

/// One tracked account: a provider plus the profile directory its CLI uses
/// (`CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex).
public struct AccountProfile: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let provider: ProviderKind
    public private(set) var label: AccountLabel
    public private(set) var directory: ProfileDirectory
    public private(set) var isEnabled: Bool
    public private(set) var pollInterval: PollInterval
    /// The account group this profile belongs to; `AppSettings` guarantees the group exists.
    public private(set) var groupID: AccountGroupID?
    /// Identity colour; `.automatic` lets `AccountStyleResolver` pick one.
    public private(set) var tint: AccountTint
    /// `nil` uses the automatic monogram.
    public private(set) var monogram: AccountMonogram?

    public init(
        id: AccountID = AccountID(),
        provider: ProviderKind,
        label: AccountLabel,
        directory: ProfileDirectory,
        isEnabled: Bool = true,
        pollInterval: PollInterval? = nil,
        groupID: AccountGroupID? = nil,
        tint: AccountTint = .automatic,
        monogram: AccountMonogram? = nil
    ) throws(ValidationError) {
        let interval = pollInterval ?? provider.defaultPollInterval
        guard interval >= provider.minimumPollInterval else {
            throw .outOfRange(
                field: "account.pollInterval",
                value: Double(interval.seconds),
                lowerBound: Double(provider.minimumPollInterval.seconds),
                upperBound: Double(PollInterval.allowedSeconds.upperBound)
            )
        }
        self.id = id
        self.provider = provider
        self.label = label
        self.directory = directory
        self.isEnabled = isEnabled
        self.pollInterval = interval
        self.groupID = groupID
        self.tint = tint
        self.monogram = monogram
    }

    /// Returns a copy with the changes applied, re-running every invariant.
    ///
    /// `groupID` and `monogram` are doubly optional: `nil` keeps the current value, `.some(nil)` removes it.
    public func updated(
        label: AccountLabel? = nil,
        directory: ProfileDirectory? = nil,
        isEnabled: Bool? = nil,
        pollInterval: PollInterval? = nil,
        groupID: AccountGroupID?? = nil,
        tint: AccountTint? = nil,
        monogram: AccountMonogram?? = nil
    ) throws(ValidationError) -> AccountProfile {
        try AccountProfile(
            id: id,
            provider: provider,
            label: label ?? self.label,
            directory: directory ?? self.directory,
            isEnabled: isEnabled ?? self.isEnabled,
            pollInterval: pollInterval ?? self.pollInterval,
            groupID: groupID ?? self.groupID,
            tint: tint ?? self.tint,
            monogram: monogram ?? self.monogram
        )
    }
}

extension AccountProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, provider, label, directory, isEnabled, pollInterval, groupID, tint, monogram
    }

    /// The id, provider, label and directory are required: without them the account is unusable and decoding fails
    /// (settings then drop only this account). Every other key is lenient: an unusable value, or a poll interval
    /// below the provider's minimum, falls back to its default with a repair note.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let id = try container.decode(AccountID.self, forKey: .id)
        let provider = try container.decode(ProviderKind.self, forKey: .provider)
        let label = try container.decode(AccountLabel.self, forKey: .label)
        let directory = try container.decode(ProfileDirectory.self, forKey: .directory)
        let isEnabled = container.decodeLenient(Bool.self, forKey: .isEnabled, default: true, report: report)
        var pollInterval = container.decodeLenientIfPresent(PollInterval.self, forKey: .pollInterval, report: report)
        if let interval = pollInterval, interval < provider.minimumPollInterval {
            report?.note(SettingsDecodeReport.path(container.codingPath + [CodingKeys.pollInterval]))
            pollInterval = nil
        }
        let groupID = container.decodeLenientIfPresent(AccountGroupID.self, forKey: .groupID, report: report)
        let tint = container.decodeLenient(AccountTint.self, forKey: .tint, default: .automatic, report: report)
        let monogram = container.decodeLenientIfPresent(AccountMonogram.self, forKey: .monogram, report: report)
        do throws(ValidationError) {
            self = try AccountProfile(
                id: id,
                provider: provider,
                label: label,
                directory: directory,
                isEnabled: isEnabled,
                pollInterval: pollInterval,
                groupID: groupID,
                tint: tint,
                monogram: monogram
            )
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(label, forKey: .label)
        try container.encode(directory, forKey: .directory)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(pollInterval, forKey: .pollInterval)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encode(tint, forKey: .tint)
        try container.encodeIfPresent(monogram, forKey: .monogram)
    }
}

/// Who a profile is signed in as. Every field is optional because sources expose different subsets.
public struct AccountIdentity: Hashable, Sendable, Codable {
    public static let maximumFieldLength = 120

    public let email: String?
    public let organization: String?
    public let plan: String?

    public init(email: String?, organization: String?, plan: String?) {
        self.email = DisplayText.sanitize(email, maximumLength: Self.maximumFieldLength)
        self.organization = DisplayText.sanitize(organization, maximumLength: Self.maximumFieldLength)
        self.plan = DisplayText.sanitize(plan, maximumLength: Self.maximumFieldLength)
    }

    public var isEmpty: Bool { email == nil && organization == nil && plan == nil }

    /// Keeps known values when a newer source only reports part of the identity.
    public func merging(_ newer: AccountIdentity) -> AccountIdentity {
        AccountIdentity(
            email: newer.email ?? email,
            organization: newer.organization ?? organization,
            plan: newer.plan ?? plan
        )
    }
}
