import CodometerCore
import CodometerPlatform
import Foundation
import Testing

@Suite("Platform seams")
struct PlatformSeamTests {
    @Test("Diagnostics payloads and the instance lock live directly in the data root")
    func directories() {
        let root = URL(fileURLWithPath: "/Users/example/Library/Caches/dev/data", isDirectory: true)
        let directories = AppDirectories(root: root, isIsolated: true)
        #expect(directories.diagnosticsDirectory.path == root.appendingPathComponent("Diagnostics").path)
        #expect(directories.diagnosticsDirectory.hasDirectoryPath)
        #expect(directories.instanceLockFile.path == root.appendingPathComponent(".lock").path)
        #expect(!directories.instanceLockFile.hasDirectoryPath)
    }

    @Test("A fixed power state reports its snapshot and yields it once")
    func fixedPower() async {
        let battery = PowerSnapshot(lowPowerMode: true, onBattery: true, batteryPercent: nil, thermal: .fair)
        let fixed = FixedPowerState(battery)
        #expect(fixed.current() == battery)
        #expect(FixedPowerState().current() == .nominalAC)
        var received: [PowerSnapshot] = []
        for await snapshot in fixed.snapshots() {
            received.append(snapshot)
        }
        #expect(received == [battery])
    }
}
