import Foundation
import Synchronization

/// Collects the coding paths of settings values that were present but unusable and were replaced by defaults.
///
/// Passed to the decoder through `userInfo[.settingsDecodeReport]`. Notes are coding paths only
/// (`appearance.scale`, `accounts[2]`), never values, so they are safe to log. At most `maximumNotes` are kept.
public final class SettingsDecodeReport: Sendable {
    /// Bounds memory for a hostile file with thousands of broken entries.
    public static let maximumNotes = 100

    private let notes = Mutex<[String]>([])

    public init() {}

    /// Paths of repaired values, in the order they were found.
    public var repairs: [String] {
        notes.withLock { $0 }
    }

    public func note(_ codingPath: String) {
        notes.withLock { notes in
            guard notes.count < Self.maximumNotes else { return }
            notes.append(codingPath)
        }
    }

    /// `appearance.floatingCard.placements.byDisplay[3]`
    public static func path(_ codingPath: [any CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result.isEmpty ? "(root)" : result
    }
}

extension CodingUserInfoKey {
    /// The `SettingsDecodeReport` that lenient settings decoding writes its repair notes to.
    public static let settingsDecodeReport: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "com.codometer.settingsDecodeReport") else {
            preconditionFailure("a non-empty user info key is always valid")
        }
        return key
    }()
}

extension Decoder {
    /// The report of the settings decode in progress, if the caller asked for one.
    public var settingsDecodeReport: SettingsDecodeReport? {
        userInfo[.settingsDecodeReport] as? SettingsDecodeReport
    }
}

extension KeyedDecodingContainer {
    /// Missing/null → fallback silently; present but undecodable (unknown raw value, failed validation, wrong type) → fallback + note.
    public func decodeLenient<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        default fallback: @autoclosure () -> T,
        report: SettingsDecodeReport?
    ) -> T {
        decodeLenientIfPresent(type, forKey: key, report: report) ?? fallback()
    }

    /// Missing/null → `nil` silently; present but undecodable → `nil` + note.
    public func decodeLenientIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key, report: SettingsDecodeReport?) -> T? {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return nil }
        do {
            return try decode(type, forKey: key)
        } catch {
            report?.note(SettingsDecodeReport.path(codingPath + [key]))
            return nil
        }
    }

    /// Undecodable elements are dropped with a note.
    ///
    /// Missing/null → `[]` silently; a value that is not an array → `[]` + note.
    public func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key, report: SettingsDecodeReport?) -> [T] {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return [] }
        let elements: [LossyElement<T>]
        do {
            elements = try decode([LossyElement<T>].self, forKey: key)
        } catch {
            report?.note(SettingsDecodeReport.path(codingPath + [key]))
            return []
        }
        var values: [T] = []
        values.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            if let value = element.value {
                values.append(value)
            } else {
                report?.note(SettingsDecodeReport.path(codingPath + [key, ArrayIndexKey(index)]))
            }
        }
        return values
    }
}

/// Decodes one array element without failing the array: `value` is `nil` when the element is unusable.
private struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct ArrayIndexKey: CodingKey {
    let intValue: Int?
    let stringValue: String

    init(_ index: Int) {
        intValue = index
        stringValue = String(index)
    }

    init?(stringValue: String) {
        return nil
    }

    init?(intValue: Int) {
        self.init(intValue)
    }
}
