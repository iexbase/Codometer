@testable import CodometerPlatform
import Darwin
import Foundation
import Testing

/// The temporary directory without symlinks (`/var/folders/…` is `/private/var/folders/…`).
private func resolvedTemporaryDirectory() throws -> String {
    let resolved = try #require(realpath(NSTemporaryDirectory(), nil))
    defer { free(resolved) }
    return String(cString: resolved)
}

private func uniqueName() -> String {
    "codometer-tests-\(UUID().uuidString)"
}

private func standard(_ environment: [String: String]) throws -> AppDirectories {
    try AppDirectories.standard(environment: environment)
}

@Suite("Data root override")
struct DataRootOverrideTests {
    @Test("Without overrides: the standard root, not isolated")
    func standardRoot() throws {
        let directories = try standard([:])
        #expect(directories.root.path.hasSuffix("/Library/Application Support/Codometer"))
        #expect(!directories.isIsolated)
        #if DEBUG
        // A debug run never moves real data.
        #else
        #endif
    }

    @Test("A root under the temporary directory is accepted and isolated")
    func acceptsTemporaryRoot() throws {
        let path = try resolvedTemporaryDirectory() + "/" + uniqueName() + "/data"
        let directories = try standard([AppDirectories.dataRootVariable: path])
        #expect(directories.root.path == path)
        #expect(directories.isIsolated)
    }

    @Test("A root under ~/Library/Caches is accepted without being created")
    func acceptsCachesRoot() throws {
        let path = NSHomeDirectory() + "/Library/Caches/" + uniqueName() + "/data"
        let directories = try standard([AppDirectories.dataRootVariable: path])
        #expect(directories.root.path == path)
        #expect(directories.isIsolated)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("The accepted root is standardized")
    func standardizesRoot() throws {
        let base = try resolvedTemporaryDirectory() + "/" + uniqueName()
        let directories = try standard([AppDirectories.dataRootVariable: base + "//x/./y/../data/"])
        #expect(directories.root.path == base + "/x/data")
    }

    @Test(
        "Relative paths and paths outside the allowed folders are refused",
        arguments: [
            "",
            "data",
            "./Library/Caches/data",
            "/Library/Caches/data",
            "~/Library/Caches/data",
            "HOME/Library/Application Support/Codometer",
            "HOME/Library/Application Support/Other",
            "HOME/Library/Caches",
            "HOME/Library/Caches/",
            "HOME/Library/CachesEvil/data",
            "HOME/Library/Caches/../Application Support/Codometer",
            "HOME/Library/Caches/x/../../Application Support/Codometer",
        ]
    )
    func refusesOutsidePaths(_ template: String) throws {
        let value = template
            .replacingOccurrences(of: "HOME", with: NSHomeDirectory())
        #expect(throws: FileAccessError.self) { try standard([AppDirectories.dataRootVariable: value]) }
    }

    @Test("A symlink among the components is refused")
    func refusesSymlinkComponent() throws {
        let base = try resolvedTemporaryDirectory() + "/" + uniqueName()
        let real = base + "/real"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        #expect(symlink(real, base + "/link") == 0)

        #expect(throws: FileAccessError.self) { try standard([AppDirectories.dataRootVariable: base + "/link/data"]) }
        #expect(throws: FileAccessError.self) { try standard([AppDirectories.dataRootVariable: base + "/link"]) }
        #expect(try standard([AppDirectories.dataRootVariable: real + "/data"]).root.path == real + "/data")
    }

    @Test("Lexical standardization")
    func standardization() {
        #expect(AppDirectories.standardizedAbsolutePath("/a//b/./c/") == "/a/b/c")
        #expect(AppDirectories.standardizedAbsolutePath("/a/b/../../../c") == "/c")
        #expect(AppDirectories.standardizedAbsolutePath("/") == "/")
        #expect(AppDirectories.standardizedAbsolutePath("a/b") == nil)
        #expect(AppDirectories.standardizedAbsolutePath("") == nil)
    }

    @Test("Allowed prefixes: ~/Library/Caches and the temporary directory in both spellings")
    func prefixes() {
        let prefixes = AppDirectories.overridePrefixes(homeDirectory: "/Users/me/", temporaryDirectory: "/tmp/")
        #expect(prefixes.contains("/Users/me/Library/Caches"))
        #expect(prefixes.contains("/tmp"))
        #expect(prefixes.contains("/private/tmp"))
    }
}
