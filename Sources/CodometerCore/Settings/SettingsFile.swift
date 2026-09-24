import Foundation

/// A decoded `settings.json`: the settings, the schema version the file declares and what was repaired.
public struct DecodedSettingsFile: Hashable, Sendable {
    public let settings: AppSettings
    /// The file's `schemaVersion`; `AppSettings.currentSchemaVersion` when it is missing or unusable (noted as a repair).
    public let schemaVersion: Int
    /// Coding paths of values replaced by defaults or dropped; empty for a clean file.
    public let repairs: [String]

    public init(settings: AppSettings, schemaVersion: Int, repairs: [String]) {
        self.settings = settings
        self.schemaVersion = schemaVersion
        self.repairs = repairs
    }

    /// Written by a newer build: load its known keys but never save over it.
    public var isReadOnly: Bool { schemaVersion > AppSettings.currentSchemaVersion }
}

extension AppSettings {
    /// Decodes a settings file leniently. Throws only when `data` is not JSON or its top level is not an object;
    /// every other problem is repaired and listed in `repairs`.
    public static func decodeFile(_ data: Data) throws -> DecodedSettingsFile {
        let report = SettingsDecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsDecodeReport] = report
        let file = try decoder.decode(SettingsFileEnvelope.self, from: data)
        return DecodedSettingsFile(settings: file.settings, schemaVersion: file.schemaVersion, repairs: report.repairs)
    }
}

/// Reads `schemaVersion` next to the settings in one pass.
private struct SettingsFileEnvelope: Decodable {
    let schemaVersion: Int
    let settings: AppSettings

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = decoder.settingsDecodeReport
        let declared = container.decodeLenientIfPresent(Int.self, forKey: .schemaVersion, report: report)
        if let declared, declared >= 1 {
            schemaVersion = declared
        } else {
            // A file Codometer wrote always declares a positive version: a missing or invalid one is a repair
            // (noted once; an undecodable value was already noted by the lenient decode).
            if report?.repairs.contains(CodingKeys.schemaVersion.stringValue) == false {
                report?.note(CodingKeys.schemaVersion.stringValue)
            }
            schemaVersion = AppSettings.currentSchemaVersion
        }
        settings = try AppSettings(from: decoder)
    }
}
