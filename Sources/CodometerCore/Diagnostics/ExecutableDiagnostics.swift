import Foundation

/// A provider CLI as Diagnostics shows it.
public struct ExecutableDiagnostics: Hashable, Sendable {
    public static let maximumPathLength = 512
    public static let maximumVersionLength = 32

    public enum Signature: Hashable, Sendable {
        /// Signed by the expected publisher.
        case trusted(publisher: String, teamID: String)
        /// Signed, but not by the expected publisher.
        case untrusted(teamID: String?)
        case unsigned
        case notFound
        /// The signature check itself failed with this `OSStatus`.
        case invalid(status: Int32)
    }

    /// The path with the home folder abbreviated ("~/.local/bin/claude"), sanitised, at most 512 characters.
    public let displayPath: String
    /// "2.1.12": `[0-9A-Za-z.+-]`, 1–32 characters; anything else is `nil`.
    public let version: String?
    public let signature: Signature
    public let modifiedAt: Date?
    public let sizeBytes: Int64?

    /// `path` is abbreviated with `homeDirectory` when given, so the stored text never names the user's home.
    public init(
        path: String,
        homeDirectory: String?,
        version: String?,
        signature: Signature,
        modifiedAt: Date?,
        sizeBytes: Int64?
    ) {
        let abbreviated = SupportTextRedaction.abbreviatingHome(in: path, homeDirectory: homeDirectory)
        displayPath = DisplayText.sanitize(abbreviated, maximumLength: Self.maximumPathLength) ?? "—"
        self.version = version.flatMap(Self.validVersion)
        self.signature = signature
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes.map { max(0, $0) }
    }

    private static func validVersion(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.utf8.count <= maximumVersionLength else { return nil }
        let valid = raw.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
        return valid ? raw : nil
    }
}
