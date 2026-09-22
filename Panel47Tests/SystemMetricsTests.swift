import Foundation
import Testing
@testable import Panel47

struct SystemMathTests {
    @Test func cpuUsageIsBusyShareOfElapsedTicks() {
        let old = CPUTicks(user: 10, system: 10, idle: 80, nice: 0)
        let new = CPUTicks(user: 20, system: 20, idle: 160, nice: 0)
        // +20 busy, +80 idle
        #expect(SystemMath.cpuUsage(from: old, to: new) == 0.2)
    }

    @Test func niceTimeCountsAsBusy() {
        let old = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 0, system: 0, idle: 50, nice: 50)
        #expect(SystemMath.cpuUsage(from: old, to: new) == 0.5)
    }

    @Test func cpuUsageSurvivesCounterWraparound() {
        let old = CPUTicks(user: UInt32.max - 4, system: 0, idle: 100, nice: 0)
        let new = CPUTicks(user: 5, system: 0, idle: 190, nice: 0) // user advanced by 10
        #expect(SystemMath.cpuUsage(from: old, to: new) == 0.1)
    }

    @Test func cpuUsageIsNilWhenNoTimeElapsed() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(SystemMath.cpuUsage(from: ticks, to: ticks) == nil)
    }

    @Test func networkDeltaSumsAcrossInterfaces() {
        let old = ["en0": InterfaceCounters(bytesIn: 100, bytesOut: 10), "en1": InterfaceCounters(bytesIn: 5, bytesOut: 5)]
        let new = ["en0": InterfaceCounters(bytesIn: 300, bytesOut: 60), "en1": InterfaceCounters(bytesIn: 15, bytesOut: 5)]
        let delta = SystemMath.networkDelta(from: old, to: new)
        #expect(delta.bytesIn == 210)
        #expect(delta.bytesOut == 50)
    }

    @Test func networkDeltaHandlesA32BitWrap() {
        let old = ["en0": InterfaceCounters(bytesIn: UInt32.max - 9, bytesOut: 0)]
        let new = ["en0": InterfaceCounters(bytesIn: 10, bytesOut: 0)]
        #expect(SystemMath.networkDelta(from: old, to: new).bytesIn == 20)
    }

    @Test func networkDeltaIgnoresInterfacesThatAppearedOrVanished() {
        let old = ["en0": InterfaceCounters(bytesIn: 100, bytesOut: 0), "en5": InterfaceCounters(bytesIn: 1, bytesOut: 1)]
        let new = ["en0": InterfaceCounters(bytesIn: 150, bytesOut: 0), "en9": InterfaceCounters(bytesIn: 999, bytesOut: 999)]
        let delta = SystemMath.networkDelta(from: old, to: new)
        #expect(delta.bytesIn == 50)
        #expect(delta.bytesOut == 0)
    }

    @Test func rateDividesByElapsedTime() {
        #expect(SystemMath.rate(bytes: 5_000, seconds: 2) == 2_500)
        #expect(SystemMath.rate(bytes: 5_000, seconds: 0) == 0)
    }

    @Test func gaugeLevelsFollowThresholds() {
        #expect(GaugeLevel.level(for: 0.5) == .normal)
        #expect(GaugeLevel.level(for: 0.75) == .warning)
        #expect(GaugeLevel.level(for: 0.9) == .critical)
    }
}

struct StatusFormatTests {
    @Test func ratesScaleThroughUnits() {
        #expect(StatusFormat.rate(0) == "0 B/S")
        #expect(StatusFormat.rate(512) == "512 B/S")
        #expect(StatusFormat.rate(1_500) == "1.5 KB/S")
        #expect(StatusFormat.rate(450_000) == "450 KB/S")
        #expect(StatusFormat.rate(12_300_000) == "12 MB/S")
        #expect(StatusFormat.rate(2_500_000_000) == "2.5 GB/S")
    }

    @Test func percentRounds() {
        #expect(StatusFormat.percent(0.874) == "87%")
        #expect(StatusFormat.percent(0.875) == "88%")
    }

    @Test func durationUsesTheTwoLargestUnits() {
        #expect(StatusFormat.duration(59 * 60) == "59M")
        #expect(StatusFormat.duration(3 * 3_600 + 12 * 60) == "3H 12M")
        #expect(StatusFormat.duration(4 * 86_400 + 5 * 3_600) == "4D 5H")
    }
}

struct SystemAlertRulesTests {
    private func metrics(
        memory: Double = 0.5,
        disk: Double = 0.5,
        battery: BatteryStatus? = nil,
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> SystemMetrics {
        SystemMetrics(
            cpuUsage: 0.1,
            memoryUsedBytes: UInt64(memory * 1_000), memoryTotalBytes: 1_000,
            diskUsedBytes: UInt64(disk * 1_000), diskTotalBytes: 1_000,
            battery: battery,
            networkDownBytesPerSecond: 0, networkUpBytesPerSecond: 0,
            uptime: 100, thermalState: thermal, loadAverage: 1
        )
    }

    @Test func aHealthyMachineRaisesNoAlert() {
        #expect(SystemAlertRules.reasons(for: metrics()).isEmpty)
    }

    @Test func aNearlyFullDiskRaisesAlert() {
        #expect(SystemAlertRules.reasons(for: metrics(disk: 0.93)) == ["STORAGE 93% FULL"])
    }

    @Test func memoryPressureRaisesAlertOnlyWhenExtreme() {
        #expect(SystemAlertRules.reasons(for: metrics(memory: 0.90)).isEmpty)
        #expect(SystemAlertRules.reasons(for: metrics(memory: 0.96)) == ["MEMORY 96% IN USE"])
    }

    @Test func aLowBatteryAlertsOnlyWhenUnplugged() {
        let unplugged = BatteryStatus(percent: 8, isCharging: false, isOnACPower: false, minutesRemaining: 12)
        let plugged = BatteryStatus(percent: 8, isCharging: true, isOnACPower: true, minutesRemaining: nil)
        #expect(SystemAlertRules.reasons(for: metrics(battery: unplugged)) == ["POWER AT 8%"])
        #expect(SystemAlertRules.reasons(for: metrics(battery: plugged)).isEmpty)
    }

    @Test func seriousHeatRaisesAlertButFairDoesNot() {
        #expect(SystemAlertRules.reasons(for: metrics(thermal: .fair)).isEmpty)
        #expect(SystemAlertRules.reasons(for: metrics(thermal: .serious)) == ["THERMAL STATE SERIOUS"])
    }

    @Test func severalProblemsAreAllReported() {
        #expect(SystemAlertRules.reasons(for: metrics(disk: 0.95, thermal: .critical)).count == 2)
    }
}

/// These read the real machine, so they check plausibility and internal
/// consistency rather than exact values.
struct LiveSystemMetricsTests {
    @Test func readingsAreSaneOnThisMachine() async throws {
        let sampler = SystemMetricsSampler()
        _ = sampler.sample()
        try await Task.sleep(nanoseconds: 400_000_000)
        let m = sampler.sample()

        #expect(m.memoryTotalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(m.memoryUsedBytes > 0 && m.memoryUsedBytes <= m.memoryTotalBytes)
        #expect(m.diskTotalBytes > 0)
        #expect(m.diskUsedBytes > 0 && m.diskUsedBytes <= m.diskTotalBytes)
        #expect(m.uptime > 0)

        let cpu = try #require(m.cpuUsage)
        #expect((0...1).contains(cpu))
        #expect(m.networkDownBytesPerSecond ?? -1 >= 0)
        #expect(m.networkUpBytesPerSecond ?? -1 >= 0)
    }

    @Test func uptimeCountsSleepUnlikeProcessInfo() {
        // Wall-clock time since boot can't be less than the time spent awake.
        #expect(SystemMetricsSampler.readUptime() >= ProcessInfo.processInfo.systemUptime)
        #expect(SystemMetricsSampler.readUptime() < 10 * 365 * 86_400)
    }

    @Test func firstSampleHasNoRatesYet() {
        let m = SystemMetricsSampler().sample()
        #expect(m.cpuUsage == nil)
        #expect(m.networkDownBytesPerSecond == nil)
    }

    @Test func batteryReadingIsAbsentOrAPercentage() {
        if let battery = SystemMetricsSampler.readBattery() {
            #expect((0...100).contains(battery.percent))
        }
    }
}
