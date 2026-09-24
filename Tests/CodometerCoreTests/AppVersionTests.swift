import CodometerCore
import Foundation
import Testing

@Suite("App version")
struct AppVersionTests {
    @Test("Parses major.minor.patch", arguments: [("1.0.0", 1, 0, 0), ("0.0.0", 0, 0, 0), ("10.20.300", 10, 20, 300)])
    func parses(raw: String, major: Int, minor: Int, patch: Int) throws {
        let version = try AppVersion(raw)
        #expect(version.major == major && version.minor == minor && version.patch == patch)
        #expect(version.description == raw)
    }

    @Test("Rejects anything else", arguments: [
        "", "1", "1.0", "1.0.0.0", "v1.0.0", "1.0.0-beta", "01.0.0", "1..0", "1.0.x", " 1.0.0", "1.-1.0", "1234567890.0.0",
        String(repeating: "1", count: 40),
    ])
    func rejects(raw: String) {
        #expect(throws: ValidationError.self) { try AppVersion(raw) }
    }

    @Test("Orders numerically, not as text")
    func ordering() throws {
        #expect(try AppVersion("1.0.0") < AppVersion("1.0.1"))
        #expect(try AppVersion("1.9.0") < AppVersion("1.10.0"))
        #expect(try AppVersion("2.0.0") > AppVersion("1.99.99"))
        #expect(try AppVersion("1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(throws: ValidationError.self) { try AppVersion(major: 1, minor: -1, patch: 0) }
    }

    @Test("Codable as a string; a bad lastLaunchedVersion is dropped")
    func coding() throws {
        let version = try AppVersion("1.0.0")
        #expect(String(decoding: try JSONEncoder().encode(version), as: UTF8.self) == #""1.0.0""#)
        #expect(try JSONDecoder().decode(AppVersion.self, from: Data(#""1.2.3""#.utf8)) == AppVersion("1.2.3"))
        let general = try JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"lastLaunchedVersion": "latest"}"#.utf8))
        #expect(general.lastLaunchedVersion == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(GeneralSettings())) as? [String: Any])
        #expect(object["lastLaunchedVersion"] == nil)
    }
}
