/// A value broke a domain invariant.
///
/// Every validated type in the domain throws this from its initialiser, so a bad
/// value can never be constructed — it is rejected where it enters the system.
public enum ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFinite(field: String)
    case outOfRange(field: String, value: Double, lowerBound: Double, upperBound: Double)
    case empty(field: String)
    case tooLong(field: String, length: Int, maximum: Int)
    case invalidCharacters(field: String)
    case notAbsolutePath(field: String)
    case duplicate(field: String, value: String)
    case inconsistent(field: String, reason: String)

    public var description: String {
        switch self {
        case .notFinite(let field):
            "\(field): value is not a finite number"
        case let .outOfRange(field, value, lowerBound, upperBound):
            "\(field): \(value) is outside \(lowerBound)...\(upperBound)"
        case .empty(let field):
            "\(field): must not be empty"
        case let .tooLong(field, length, maximum):
            "\(field): length \(length) exceeds \(maximum)"
        case .invalidCharacters(let field):
            "\(field): contains characters that are not allowed"
        case .notAbsolutePath(let field):
            "\(field): must be an absolute path"
        case let .duplicate(field, value):
            "\(field): duplicate value \(value)"
        case let .inconsistent(field, reason):
            "\(field): \(reason)"
        }
    }

    /// Wraps the error for `Decodable` initialisers so decoding fails at a precise coding path.
    public func decodingError(at codingPath: [any CodingKey]) -> DecodingError {
        .dataCorrupted(
            DecodingError.Context(codingPath: codingPath, debugDescription: description, underlyingError: self)
        )
    }
}
