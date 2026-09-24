import CodometerPlatform
import Darwin
import Foundation
import Testing

@Suite("Exclusive file creation")
struct SecureFileIOExclusiveTests {
    @Test("A new private file is created, written in pieces and closed")
    func createsAndWrites() throws {
        let directory = try TemporaryDirectory()
        let url = directory.file("export.json.partial")
        let file = try SecureFileIO.createExclusive(at: url)
        try file.write("{\"format\":")
        try file.write(Data("\"codometer-history\"}".utf8))
        try file.close()
        #expect(file.isClosed)
        // Closing twice is harmless, and writing afterwards fails instead of corrupting something else.
        try file.close()
        #expect(throws: FileAccessError.self) { try file.write("more") }

        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"format\":\"codometer-history\"}")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test("An existing file or symbolic link at the same name is refused, and its target is untouched")
    func refusesExistingAndSymlinks() throws {
        let directory = try TemporaryDirectory()
        let taken = directory.file("taken.json")
        try Data("original".utf8).write(to: taken)
        #expect(throws: FileAccessError.self) { _ = try SecureFileIO.createExclusive(at: taken) }
        #expect(try String(contentsOf: taken, encoding: .utf8) == "original")

        let target = directory.file("target.json")
        try Data("target".utf8).write(to: target)
        let link = directory.file("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: FileAccessError.self) { _ = try SecureFileIO.createExclusive(at: link) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "target")
    }

    @Test("A missing directory is reported instead of created")
    func refusesMissingDirectory() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("nowhere/file.json")
        #expect(throws: FileAccessError.self) { _ = try SecureFileIO.createExclusive(at: url) }
    }

    @Test("Only regular files are unlinked, and a missing one is not an error")
    func unlinksRegularFilesOnly() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("leftover.partial")
        try Data("x".utf8).write(to: file)
        #expect(try SecureFileIO.unlinkRegularFile(at: file))
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
        #expect(try SecureFileIO.unlinkRegularFile(at: file) == false)

        let target = directory.file("kept.json")
        try Data("kept".utf8).write(to: target)
        let link = directory.file("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: FileAccessError.notRegularFile(path: link.path)) {
            _ = try SecureFileIO.unlinkRegularFile(at: link)
        }
        #expect(FileManager.default.fileExists(atPath: target.path))

        let folder = directory.url.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: FileAccessError.notRegularFile(path: folder.path)) {
            _ = try SecureFileIO.unlinkRegularFile(at: folder)
        }
    }
}
