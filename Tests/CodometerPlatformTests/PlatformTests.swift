import CodometerPlatform
import Darwin
import Foundation
import Testing

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codometer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name, isDirectory: false)
    }
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

private func lines(_ chunk: TailChunk) -> [String] {
    chunk.lines.map { String(decoding: $0, as: UTF8.self) }
}

@Suite("File tail")
struct FileTailTests {
    @Test("Returns only complete lines and resumes after them")
    func incrementalLines() throws {
        let directory = try TemporaryDirectory()
        let log = directory.file("log.jsonl")
        try Data("one\ntwo\nthr".utf8).write(to: log)

        let first = try FileTail.read(at: log, after: nil, initialTailBytes: 1_024, maximumReadBytes: 1_024)
        #expect(lines(first) == ["one", "two"])

        try append("ee\nfour\n", to: log)
        let second = try FileTail.read(at: log, after: first.cursor, initialTailBytes: 1_024, maximumReadBytes: 1_024)
        #expect(lines(second) == ["three", "four"])
        #expect(!second.didRestart)

        let third = try FileTail.read(at: log, after: second.cursor, initialTailBytes: 1_024, maximumReadBytes: 1_024)
        #expect(third.lines.isEmpty)
    }

    @Test("A replaced or truncated file restarts from its tail")
    func restartOnReplacement() throws {
        let directory = try TemporaryDirectory()
        let log = directory.file("log.jsonl")
        try Data("a\nb\n".utf8).write(to: log)
        let first = try FileTail.read(at: log, after: nil, initialTailBytes: 1_024, maximumReadBytes: 1_024)

        try FileManager.default.removeItem(at: log)
        try Data("c\n".utf8).write(to: log)
        let replaced = try FileTail.read(at: log, after: first.cursor, initialTailBytes: 1_024, maximumReadBytes: 1_024)
        #expect(replaced.didRestart)
        #expect(lines(replaced) == ["c"])
    }

    @Test("The initial read of a large file skips its partial first line")
    func initialTail() throws {
        let directory = try TemporaryDirectory()
        let log = directory.file("log.jsonl")
        try Data("0123456789\nshort\nlast\n".utf8).write(to: log)
        let chunk = try FileTail.read(at: log, after: nil, initialTailBytes: 14, maximumReadBytes: 1_024)
        #expect(lines(chunk) == ["short", "last"])
    }

    @Test("Symlinks are refused")
    func refusesSymlinks() throws {
        let directory = try TemporaryDirectory()
        let target = directory.file("target")
        try Data("secret\n".utf8).write(to: target)
        let link = directory.file("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: FileAccessError.notRegularFile(path: link.path)) {
            try FileTail.read(at: link, after: nil, initialTailBytes: 1_024, maximumReadBytes: 1_024)
        }
        #expect(throws: FileAccessError.notRegularFile(path: link.path)) {
            try SecureFileIO.readRegularFile(at: link, maximumBytes: 1_024)
        }
    }
}

@Suite("Secure file I/O")
struct SecureFileIOTests {
    @Test("Size limits are enforced")
    func sizeLimit() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("big")
        try Data(repeating: 65, count: 2_000).write(to: file)
        #expect(throws: FileAccessError.tooLarge(path: file.path, size: 2_000, limit: 1_000)) {
            try SecureFileIO.readRegularFile(at: file, maximumBytes: 1_000)
        }
        #expect(try SecureFileIO.readRegularFile(at: file, maximumBytes: 2_000).count == 2_000)
    }

    @Test("Atomic writes replace the file with owner-only permissions")
    func atomicWrite() throws {
        let directory = try TemporaryDirectory()
        let file = directory.file("settings.json")
        try SecureFileIO.writeAtomically(Data("v1".utf8), to: file)
        try SecureFileIO.writeAtomically(Data("v2".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "v2")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.url.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("Private directories are created with 0700")
    func privateDirectory() throws {
        let directory = try TemporaryDirectory()
        let nested = directory.url.appendingPathComponent("a/b", isDirectory: true)
        try SecureFileIO.ensurePrivateDirectory(at: nested)
        let attributes = try FileManager.default.attributesOfItem(atPath: nested.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test("Listing a missing directory yields nothing")
    func missingDirectory() throws {
        let directory = try TemporaryDirectory()
        #expect(try SecureFileIO.regularFileNames(in: directory.url.appendingPathComponent("absent")).isEmpty)
    }
}

@Suite("Process runner")
struct ProcessRunnerTests {
    private func request(_ path: String, _ arguments: [String], environment: [String: String] = [:]) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: environment,
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
    }

    @Test("Runs a command with an explicit environment and working directory")
    func runsCommand() async throws {
        let registry = ChildProcessRegistry()
        let result = try await ProcessRunner(registry: registry).run(
            request("/bin/sh", ["-c", "printf '%s|%s' \"$GREETING\" \"$(pwd -P)\"; printf err >&2"], environment: ["GREETING": "hi"]),
            timeout: .seconds(10),
            maximumOutputBytes: 1_024
        )
        #expect(result.exit == .exited(code: 0))
        #expect(String(decoding: result.standardOutput, as: UTF8.self) == "hi|/private/tmp")
        #expect(String(decoding: result.standardError, as: UTF8.self) == "err")
        #expect(!registry.contains(result.processID))
    }

    @Test("Nothing is inherited from the parent environment")
    func environmentIsolated() async throws {
        let result = try await ProcessRunner().run(
            request("/usr/bin/env", []),
            timeout: .seconds(10),
            maximumOutputBytes: 64_000
        )
        #expect(String(decoding: result.standardOutput, as: UTF8.self).isEmpty)
    }

    @Test("Non-zero exit codes are reported")
    func exitCode() async throws {
        let result = try await ProcessRunner().run(request("/bin/sh", ["-c", "exit 3"]), timeout: .seconds(10), maximumOutputBytes: 64)
        #expect(result.exit == .exited(code: 3))
        #expect(!result.exit.isSuccess)
    }

    @Test("A hanging command is killed at the timeout")
    func timeout() async {
        let started = Date()
        await #expect(throws: ProcessRunError.timedOut(seconds: 0.3)) {
            try await ProcessRunner().run(self.request("/bin/sleep", ["30"]), timeout: .milliseconds(300), maximumOutputBytes: 64)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("Output beyond the cap aborts the command")
    func outputCap() async {
        await #expect(throws: ProcessRunError.outputTooLarge(limit: 10_000)) {
            try await ProcessRunner().run(self.request("/usr/bin/yes", []), timeout: .seconds(20), maximumOutputBytes: 10_000)
        }
    }

    @Test("Relative executables and NUL bytes are rejected before spawning")
    func invalidRequests() async {
        await #expect(throws: ProcessRunError.self) {
            try await ProcessRunner().run(
                ProcessRequest(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["a\u{0}b"], environment: [:], workingDirectory: URL(fileURLWithPath: "/tmp")),
                timeout: .seconds(5),
                maximumOutputBytes: 64
            )
        }
    }

    @Test("Line channel exchanges newline-delimited messages")
    func lineChannel() async throws {
        let channel = try LineChannel.launch(request("/bin/cat", []), maximumLineBytes: 1_024, registry: nil)
        try channel.send(Data(#"{"id":1}"#.utf8))
        try channel.send(Data(#"{"id":2}"#.utf8))
        var iterator = channel.lines.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first.map { String(decoding: $0, as: UTF8.self) } == #"{"id":1}"#)
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == #"{"id":2}"#)
        #expect(throws: ProcessRunError.self) { try channel.send(Data("multi\nline".utf8)) }
        channel.terminate()
        #expect(await iterator.next() == nil)
    }

    @Test("Serial gate runs operations one at a time")
    func serialGate() async {
        let gate = AsyncSerialGate()
        let counter = ConcurrencyCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    try? await Task.sleep(for: .milliseconds(5))
                    await counter.leave()
                    await gate.release()
                }
            }
        }
        #expect(await counter.maximum == 1)
    }
}

private actor ConcurrencyCounter {
    private var current = 0
    private(set) var maximum = 0

    func enter() {
        current += 1
        maximum = max(maximum, current)
    }

    func leave() {
        current -= 1
    }
}

@Suite("Code signatures and processes")
struct SecurityTests {
    @Test("Apple's own binaries are not accepted as a third-party publisher")
    func wrongPublisher() async {
        await #expect(throws: CodeSignatureError.wrongPublisher(path: "/bin/ls", expected: "Anthropic PBC")) {
            try await CodeSignatureVerifier().verify(URL(fileURLWithPath: "/bin/ls"), publisher: .anthropic)
        }
    }

    @Test("Missing executables are reported as not found")
    func missing() async {
        await #expect(throws: ExecutableLookupError.notFound(searched: ["/nonexistent/claude"])) {
            try await TrustedExecutableLocator(verifier: CodeSignatureVerifier())
                .locate(candidates: [URL(fileURLWithPath: "/nonexistent/claude")], publisher: .anthropic)
        }
    }

    @Test("An unsigned script is refused even when it is executable")
    func unsignedScript() async throws {
        let directory = try TemporaryDirectory()
        let script = directory.file("claude")
        try Data("#!/bin/sh\necho pwned\n".utf8).write(to: script)
        chmod(script.path, 0o755)
        await #expect(throws: ExecutableLookupError.self) {
            try await TrustedExecutableLocator(verifier: CodeSignatureVerifier()).locate(candidates: [script], publisher: .anthropic)
        }
    }

    @Test("Process liveness and start time")
    func processInspector() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessInspector.isAlive(pid))
        let start = try #require(ProcessInspector.startTime(of: pid))
        #expect(start <= Date())
        #expect(!ProcessInspector.isAlive(0))
        #expect(ProcessInspector.startTime(of: -1) == nil)
    }
}
