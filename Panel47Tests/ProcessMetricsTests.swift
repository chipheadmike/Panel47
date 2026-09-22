import Foundation
import Testing
@testable import Panel47

struct ProcessMathTests {
    private func reading(_ pid: Int32, _ name: String = "app", uid: UInt32 = 501, cpu: UInt64 = 0, mem: UInt64 = 0) -> ProcessReading {
        ProcessReading(pid: pid, name: name, uid: uid, cpuTimeNanos: cpu, footprintBytes: mem)
    }

    @Test func cpuPercentIsShareOfOneCore() {
        // 0.5 s of CPU in 1 s of wall time
        #expect(ProcessMath.cpuPercent(previousNanos: 0, currentNanos: 500_000_000, wallSeconds: 1) == 50)
        // two cores busy for the whole second
        #expect(ProcessMath.cpuPercent(previousNanos: 1_000, currentNanos: 2_000_001_000, wallSeconds: 1) == 200)
    }

    @Test func cpuPercentIsNilWhenTheCounterGoesBackwards() {
        #expect(ProcessMath.cpuPercent(previousNanos: 900, currentNanos: 100, wallSeconds: 1) == nil)
        #expect(ProcessMath.cpuPercent(previousNanos: 0, currentNanos: 100, wallSeconds: 0) == nil)
    }

    @Test func aReusedPidIsNotComparedWithTheOldProcess() {
        let previous: [Int32: ProcessReading] = [7: reading(7, "old", cpu: 5_000_000_000)]
        let entries = ProcessMath.entries(
            current: [reading(7, "new", cpu: 1_000)],
            previous: previous, wallSeconds: 1, ownUID: 501, ownPID: 1
        )
        #expect(entries[0].cpuPercent == nil)
    }

    @Test func aBrandNewProcessHasNoCPUFigureYet() {
        let entries = ProcessMath.entries(current: [reading(9)], previous: [:], wallSeconds: 1, ownUID: 501, ownPID: 1)
        #expect(entries[0].cpuPercent == nil)
    }

    @Test func sortingByCPUPutsTheBusiestFirstAndUnknownLast() {
        let entries = [
            ProcessEntry(pid: 1, name: "a", cpuPercent: 5, footprintBytes: 100, canTerminate: true),
            ProcessEntry(pid: 2, name: "b", cpuPercent: nil, footprintBytes: 900, canTerminate: true),
            ProcessEntry(pid: 3, name: "c", cpuPercent: 80, footprintBytes: 10, canTerminate: true),
        ]
        #expect(ProcessMath.top(entries, by: .cpu, limit: 10).map(\.pid) == [3, 1, 2])
    }

    @Test func sortingByMemoryPutsTheBiggestFirst() {
        let entries = [
            ProcessEntry(pid: 1, name: "a", cpuPercent: 5, footprintBytes: 100, canTerminate: true),
            ProcessEntry(pid: 2, name: "b", cpuPercent: nil, footprintBytes: 900, canTerminate: true),
            ProcessEntry(pid: 3, name: "c", cpuPercent: 80, footprintBytes: 10, canTerminate: true),
        ]
        #expect(ProcessMath.top(entries, by: .memory, limit: 2).map(\.pid) == [2, 1])
    }

    @Test func terminationIsRefusedForSystemOthersAndSelf() {
        #expect(ProcessMath.entries(current: [reading(500)], previous: [:], wallSeconds: 1, ownUID: 501, ownPID: 1)[0].canTerminate)
        #expect(!TerminationRules.canTerminate(pid: 1, uid: 501, ownUID: 501, ownPID: 999))
        #expect(!TerminationRules.canTerminate(pid: 0, uid: 501, ownUID: 501, ownPID: 999))
        #expect(!TerminationRules.canTerminate(pid: 999, uid: 501, ownUID: 501, ownPID: 999))
        #expect(!TerminationRules.canTerminate(pid: 500, uid: 0, ownUID: 501, ownPID: 999))
    }
}

struct ProcessListModelTests {
    private func model(signal: @escaping (Int32, Int32) -> Int32 = { _, _ in 0 }) -> ProcessListModel {
        let readings = [
            ProcessReading(pid: 100, name: "editor", uid: 501, cpuTimeNanos: 0, footprintBytes: 500),
            ProcessReading(pid: 1, name: "launchd", uid: 501, cpuTimeNanos: 0, footprintBytes: 900),
        ]
        let model = ProcessListModel(reader: { readings }, signaler: signal, ownUID: 501, ownPID: 4242)
        model.refresh()
        return model
    }

    @Test func terminationNeedsArmingFirst() {
        var signals: [(Int32, Int32)] = []
        let model = model { signals.append(($0, $1)); return 0 }

        model.confirmTerminate(100)
        #expect(signals.isEmpty)

        model.arm(100)
        model.confirmTerminate(100)
        #expect(signals.count == 1)
        #expect(signals[0].0 == 100 && signals[0].1 == SIGTERM)
        #expect(model.armedPID == nil)
    }

    @Test func confirmingADifferentProcessThanTheArmedOneDoesNothing() {
        var signals = 0
        let model = model { _, _ in signals += 1; return 0 }
        model.arm(100)
        model.confirmTerminate(1)
        #expect(signals == 0)
    }

    @Test func protectedProcessesCannotBeArmed() {
        var signals = 0
        let model = model { _, _ in signals += 1; return 0 }
        model.arm(1)
        #expect(model.armedPID == nil)
        model.confirmTerminate(1)
        #expect(signals == 0)
    }

    @Test func cancelDisarms() {
        let model = model()
        model.arm(100)
        model.cancel()
        #expect(model.armedPID == nil)
    }

    @Test func aFailedSignalIsReported() {
        let model = model { _, _ in -1 }
        model.arm(100)
        model.confirmTerminate(100)
        #expect(model.notice?.hasPrefix("COULD NOT TERMINATE EDITOR") == true)
    }

    @Test func armedProcessThatQuitsIsDisarmed() {
        var present = true
        let model = ProcessListModel(
            reader: { present ? [ProcessReading(pid: 100, name: "editor", uid: 501, cpuTimeNanos: 0, footprintBytes: 1)] : [] },
            signaler: { _, _ in 0 }, ownUID: 501, ownPID: 4242
        )
        model.refresh()
        model.arm(100)
        present = false
        model.refresh()
        #expect(model.armedPID == nil)
    }
}

/// Reads the real machine, so these check plausibility only.
struct LiveProcessTests {
    @Test func thisTestProcessIsListedWithSaneNumbers() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let reading = try #require(ProcessSampler.readProcesses().first { $0.pid == me })
        #expect(reading.uid == getuid())
        #expect(reading.footprintBytes > 0)
        #expect(reading.cpuTimeNanos > 0)
    }

    @Test func aBusyLoopShowsUpAsCPUUse() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let before = try #require(ProcessSampler.read(pid: me))
        let start = Date()
        var x = 0.0
        while Date().timeIntervalSince(start) < 0.5 { x += sin(x) + 1 }
        let after = try #require(ProcessSampler.read(pid: me))
        let percent = try #require(ProcessMath.cpuPercent(
            previousNanos: before.cpuTimeNanos, currentNanos: after.cpuTimeNanos,
            wallSeconds: Date().timeIntervalSince(start)
        ))
        // One busy thread for the whole window: roughly one core, allowing scheduling noise.
        #expect(percent > 60 && percent < 130, "measured \(percent)% (x=\(x))")
    }

    @Test func terminatingARealChildProcessEndToEnd() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let pid = child.processIdentifier

        // The real reader and the real kill(2), with room to list every process.
        let model = ProcessListModel(rowLimit: 100_000)
        model.refresh()
        #expect(model.rows.contains { $0.pid == pid && $0.name == "sleep" })

        model.confirmTerminate(pid) // not armed yet: must do nothing
        #expect(child.isRunning)

        model.arm(pid)
        model.confirmTerminate(pid)
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGTERM)
        #expect(model.notice == "TERMINATION SIGNAL SENT TO SLEEP")
    }

    @Test func machTimeConvertsToNanosecondsMonotonically() {
        #expect(ProcessSampler.nanoseconds(fromMachTime: 0) == 0)
        #expect(ProcessSampler.nanoseconds(fromMachTime: 2_000_000) >= ProcessSampler.nanoseconds(fromMachTime: 1_000_000))
    }
}
