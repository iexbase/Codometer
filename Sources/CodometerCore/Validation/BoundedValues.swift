import Foundation

/// A user-visible account name: trimmed, 1–40 characters, no control characters.
public struct AccountLabel: Hashable, Sendable, CustomStringConvertible {
    public static let maximumLength = 40

    public let value: String

    public init(validating raw: String) throws(ValidationError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty(field: "account.label") }
        guard trimmed.count <= Self.maximumLength else {
            throw .tooLong(field: "account.label", length: trimmed.count, maximum: Self.maximumLength)
        }
        guard !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw .invalidCharacters(field: "account.label")
        }
        value = trimmed
    }

    public var description: String { value }
}

extension AccountLabel: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try String(from: decoder)
        do throws(ValidationError) {
            self = try AccountLabel(validating: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// An absolute, standardised directory path such as `/Users/me/.claude-work`.
public struct ProfileDirectory: Hashable, Sendable, CustomStringConvertible {
    public static let maximumLength = 1_024

    public let path: String

    public init(validating raw: String) throws(ValidationError) {
        guard !raw.isEmpty else { throw .empty(field: "account.directory") }
        guard raw.hasPrefix("/") else { throw .notAbsolutePath(field: "account.directory") }
        guard !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw .invalidCharacters(field: "account.directory")
        }
        let standardized = (raw as NSString).standardizingPath
        guard standardized.utf8.count <= Self.maximumLength else {
            throw .tooLong(field: "account.directory", length: standardized.utf8.count, maximum: Self.maximumLength)
        }
        path = standardized
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public var lastComponent: String { (path as NSString).lastPathComponent }

    public var description: String { path }
}

extension ProfileDirectory: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try String(from: decoder)
        do throws(ValidationError) {
            self = try ProfileDirectory(validating: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try path.encode(to: encoder)
    }
}

/// How often an account is refreshed in the background: 1 minute to 1 hour.
public struct PollInterval: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let allowedSeconds: ClosedRange<Int> = 60...3_600

    public let seconds: Int

    public init(seconds: Int) throws(ValidationError) {
        guard Self.allowedSeconds.contains(seconds) else {
            throw .outOfRange(
                field: "pollInterval",
                value: Double(seconds),
                lowerBound: Double(Self.allowedSeconds.lowerBound),
                upperBound: Double(Self.allowedSeconds.upperBound)
            )
        }
        self.seconds = seconds
    }

    fileprivate init(trustedSeconds: Int) {
        seconds = trustedSeconds
    }

    public var timeInterval: TimeInterval { TimeInterval(seconds) }

    public var description: String { "\(seconds)s" }

    public static func < (lhs: PollInterval, rhs: PollInterval) -> Bool {
        lhs.seconds < rhs.seconds
    }

    static func constant(_ seconds: Int) -> PollInterval {
        precondition(allowedSeconds.contains(seconds), "constant poll interval out of range")
        return PollInterval(trustedSeconds: seconds)
    }
}

extension PollInterval: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Int(from: decoder)
        do throws(ValidationError) {
            self = try PollInterval(seconds: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try seconds.encode(to: encoder)
    }
}

/// The length of a usage-limit window, from one minute to about two months.
public struct WindowDuration: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let allowedMinutes: ClosedRange<Int> = 1...(60 * 24 * 62)

    public let minutes: Int

    public init(minutes: Int) throws(ValidationError) {
        guard Self.allowedMinutes.contains(minutes) else {
            throw .outOfRange(
                field: "window.duration",
                value: Double(minutes),
                lowerBound: Double(Self.allowedMinutes.lowerBound),
                upperBound: Double(Self.allowedMinutes.upperBound)
            )
        }
        self.minutes = minutes
    }

    private init(trustedMinutes: Int) {
        minutes = trustedMinutes
    }

    public static let fiveHours = WindowDuration(trustedMinutes: 300)
    public static let oneDay = WindowDuration(trustedMinutes: 1_440)
    public static let oneWeek = WindowDuration(trustedMinutes: 10_080)

    public var timeInterval: TimeInterval { TimeInterval(minutes) * 60 }

    public var description: String { "\(minutes)m" }

    public static func < (lhs: WindowDuration, rhs: WindowDuration) -> Bool {
        lhs.minutes < rhs.minutes
    }
}

extension WindowDuration: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try Int(from: decoder)
        do throws(ValidationError) {
            self = try WindowDuration(minutes: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try minutes.encode(to: encoder)
    }
}

/// A stable machine identifier such as a limit or window id: 1–64 characters of `[A-Za-z0-9._-]`.
public enum StableIdentifier {
    public static let maximumLength = 64

    public static func validate(_ raw: String, field: String) throws(ValidationError) -> String {
        guard !raw.isEmpty else { throw .empty(field: field) }
        guard raw.utf8.count <= maximumLength else {
            throw .tooLong(field: field, length: raw.utf8.count, maximum: maximumLength)
        }
        let allowed = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
        guard allowed else { throw .invalidCharacters(field: field) }
        return raw
    }
}

/// Free text that came from another program: trimmed, control characters removed, length capped.
public enum DisplayText {
    public static func sanitize(_ raw: String?, maximumLength: Int) -> String? {
        guard let raw else { return nil }
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > maximumLength else { return cleaned }
        return String(cleaned.prefix(maximumLength - 1)) + "…"
    }
}
