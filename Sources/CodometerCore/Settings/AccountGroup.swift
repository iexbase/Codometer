import Foundation

public struct AccountGroupID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

extension AccountGroupID: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try UUID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

/// A named set of accounts such as «Работа» or «Личное», with per-group notification mutes.
public struct AccountGroup: Hashable, Sendable, Identifiable {
    public let id: AccountGroupID
    /// Validated like an account label: trimmed, 1–40 characters, no control characters.
    public var name: AccountLabel
    /// Suppresses "finished" and "needs attention" notifications for the group's accounts.
    public var mutesSessionAlerts: Bool
    /// Suppresses threshold and reset notifications for the group's accounts.
    public var mutesUsageAlerts: Bool

    public init(
        id: AccountGroupID = AccountGroupID(),
        name: AccountLabel,
        mutesSessionAlerts: Bool = false,
        mutesUsageAlerts: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mutesSessionAlerts = mutesSessionAlerts
        self.mutesUsageAlerts = mutesUsageAlerts
    }
}

extension AccountGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, mutesSessionAlerts, mutesUsageAlerts
    }

    /// The id and name are required (settings drop a group without them); the mutes are lenient.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        id = try container.decode(AccountGroupID.self, forKey: .id)
        name = try container.decode(AccountLabel.self, forKey: .name)
        mutesSessionAlerts = container.decodeLenient(Bool.self, forKey: .mutesSessionAlerts, default: false, report: report)
        mutesUsageAlerts = container.decodeLenient(Bool.self, forKey: .mutesUsageAlerts, default: false, report: report)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(mutesSessionAlerts, forKey: .mutesSessionAlerts)
        try container.encode(mutesUsageAlerts, forKey: .mutesUsageAlerts)
    }
}
