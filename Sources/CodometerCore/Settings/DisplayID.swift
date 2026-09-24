import Foundation

/// A display's stable identity: the `CGDisplayCreateUUIDFromDisplayID` string in canonical uppercase form.
///
/// `CGDirectDisplayID` is never stored because it changes between boots and reconnects.
public struct DisplayID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    /// Accepts any UUID spelling (`37d8832a-…`) and stores the canonical uppercase form.
    public init(_ raw: String) throws(ValidationError) {
        guard !raw.isEmpty else { throw .empty(field: "display.id") }
        guard raw.utf8.count == 36, let uuid = UUID(uuidString: raw) else {
            throw .invalidCharacters(field: "display.id")
        }
        rawValue = uuid.uuidString
    }

    public var description: String { rawValue }

    public static func < (lhs: DisplayID, rhs: DisplayID) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension DisplayID: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try String(from: decoder)
        do throws(ValidationError) {
            self = try DisplayID(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

/// A display a surface was left on: its id plus its name, used only to re-adopt a display whose UUID changed
/// (some docks and KVM switches report a new UUID).
public struct RememberedDisplay: Hashable, Sendable {
    public static let maximumNameLength = 64

    public let id: DisplayID
    /// Sanitised, at most 64 characters.
    public let name: String?

    public init(id: DisplayID, name: String?) {
        self.id = id
        self.name = DisplayText.sanitize(name, maximumLength: Self.maximumNameLength)
    }
}

extension RememberedDisplay: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    /// The id is required; an unusable name is dropped with a repair note.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(DisplayID.self, forKey: .id)
        let name = container.decodeLenientIfPresent(String.self, forKey: .name, report: decoder.settingsDecodeReport)
        self.init(id: id, name: name)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

/// Which display a surface (island or floating card) appears on.
public enum DisplayPolicy: Hashable, Sendable {
    /// The display it was last dropped on, while connected; otherwise the main display (default).
    case whereLeft
    /// Always the main display (the one with the menu bar).
    case main
    /// A specific display while connected; otherwise the main display.
    case display(DisplayID)
}

extension DisplayPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    private enum Kind: String, Codable {
        case whereLeft, main, display
    }

    /// `{"kind": "whereLeft"}`, `{"kind": "main"}`, `{"kind": "display", "id": "…"}`. Never fails: an unknown kind,
    /// a bad id or a value that is not an object decodes as `.whereLeft` with a repair note.
    public init(from decoder: any Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .whereLeft:
                self = .whereLeft
            case .main:
                self = .main
            case .display:
                self = .display(try container.decode(DisplayID.self, forKey: .id))
            }
        } catch {
            decoder.settingsDecodeReport?.note(SettingsDecodeReport.path(decoder.codingPath))
            self = .whereLeft
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .whereLeft:
            try container.encode(Kind.whereLeft, forKey: .kind)
        case .main:
            try container.encode(Kind.main, forKey: .kind)
        case .display(let id):
            try container.encode(Kind.display, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}
