/// A release version `major.minor.patch`, such as `1.0.0`.
public struct AppVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// Longer strings are rejected before parsing.
    public static let maximumLength = 32

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) throws(ValidationError) {
        for component in [major, minor, patch] where component < 0 {
            throw .outOfRange(field: "appVersion", value: Double(component), lowerBound: 0, upperBound: Double(Int32.max))
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Exactly three dot-separated decimal numbers without leading zeros (`1.0.0`, `10.2.13`).
    public init(_ string: String) throws(ValidationError) {
        guard !string.isEmpty else { throw .empty(field: "appVersion") }
        guard string.utf8.count <= Self.maximumLength else {
            throw .tooLong(field: "appVersion", length: string.utf8.count, maximum: Self.maximumLength)
        }
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw .inconsistent(field: "appVersion", reason: "expected major.minor.patch")
        }
        var numbers: [Int] = []
        for part in parts {
            guard
                !part.isEmpty,
                part.utf8.count <= 9,
                part.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
                part == "0" || !part.hasPrefix("0"),
                let number = Int(part)
            else { throw .invalidCharacters(field: "appVersion") }
            numbers.append(number)
        }
        try self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

extension AppVersion: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try String(from: decoder)
        do throws(ValidationError) {
            self = try AppVersion(raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try description.encode(to: encoder)
    }
}
