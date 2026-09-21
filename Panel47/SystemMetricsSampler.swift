import Combine
import Darwin
import Foundation
import IOKit.ps

/// Reads live numbers from the operating system — Mach counters for CPU and
/// memory, the volume APIs for storage, IOKit for the battery, and interface
/// byte counters for the network. CPU and network are rates, so they need a
/// previous sample to compare against; the first sample reports nil for both.
final class SystemMetricsSampler {
    private var lastCPU: CPUTicks?
    private var lastNetwork: [String: InterfaceCounters]?
    private var lastNetworkTime: Date?

    func sample(now: Date = Date()) -> SystemMetrics {
        let ticks = Self.readCPUTicks()
        var cpuUsage: Double?
        if let previous = lastCPU, let current = ticks {
            cpuUsage = SystemMath.cpuUsage(from: previous, to: current)
        }
        lastCPU = ticks

        var down: Double?
        var up: Double?
        let counters = Self.readNetworkCounters()
        if let previous = lastNetwork, let previousTime = lastNetworkTime {
            let delta = SystemMath.networkDelta(from: previous, to: counters)
            let seconds = now.timeIntervalSince(previousTime)
            down = SystemMath.rate(bytes: delta.bytesIn, seconds: seconds)
            up = SystemMath.rate(bytes: delta.bytesOut, seconds: seconds)
        }
        lastNetwork = counters
        lastNetworkTime = now

        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memory = Self.readMemory() ?? (used: 0, total: physicalMemory)
        let disk = Self.readDisk() ?? (used: 0, total: 0)

        return SystemMetrics(
            cpuUsage: cpuUsage,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            battery: Self.readBattery(),
            networkDownBytesPerSecond: down,
            networkUpBytesPerSecond: up,
            uptime: Self.readUptime(),
            thermalState: ProcessInfo.processInfo.thermalState,
            loadAverage: Self.readLoadAverage()
        )
    }

    // MARK: - System calls

    static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks is indexed by CPU_STATE_USER, SYSTEM, IDLE, NICE.
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    /// "Memory used" the way Activity Monitor reports it: app memory (anonymous
    /// pages minus purgeable ones) plus wired plus compressed.
    static func readMemory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let total = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(getpagesize())
        let appPages = UInt64(stats.internal_page_count) &- UInt64(min(stats.purgeable_count, stats.internal_page_count))
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (min(pages * pageSize, total), total)
    }

    /// The volume your files live on, with "available" counted the way Finder
    /// does (free space plus what macOS can reclaim).
    static func readDisk() -> (used: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0 else { return nil }

        let used = max(0, Int64(total) - available)
        return (UInt64(used), UInt64(total))
    }

    static func readBattery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = description[kIOPSTimeToEmptyKey] as? Int

            return BatteryStatus(
                percent: min(100, current * 100 / maximum),
                isCharging: charging,
                isOnACPower: onAC,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return nil
    }

    /// Per-interface byte counters for Wi-Fi/Ethernet/Thunderbolt ("en*").
    static func readNetworkCounters() -> [String: InterfaceCounters] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var counters: [String: InterfaceCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            if let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data {
                let name = String(cString: entry.ifa_name)
                if name.hasPrefix("en") {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    counters[name] = InterfaceCounters(bytesIn: stats.ifi_ibytes, bytesOut: stats.ifi_obytes)
                }
            }
            cursor = entry.ifa_next
        }
        return counters
    }

    /// Wall-clock time since boot, like the `uptime` command. `ProcessInfo.systemUptime`
    /// isn't used because it stops counting while the Mac sleeps.
    static func readUptime() -> TimeInterval {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let bootTime = TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - bootTime)
    }

    static func readLoadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : nil
    }
}

/// Samples once a second, but only while the status panel is on screen.
final class SystemStatusModel: ObservableObject {
    static let historyLength = 60

    @Published private(set) var metrics: SystemMetrics
    @Published private(set) var cpuHistory: [Double] = []
    /// Scale for the network bars: the recent peak, never below 1 MB/s, so a
    /// single big download doesn't flatten every later reading.
    @Published private(set) var networkPeak: Double = 1_000_000

    private let sampler: SystemMetricsSampler
    private var timer: Timer?

    init() {
        let sampler = SystemMetricsSampler()
        self.sampler = sampler
        metrics = sampler.sample()
    }

    func start() {
        guard timer == nil else { return }
        metrics = sampler.sample()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let latest = sampler.sample()
        metrics = latest

        if let cpu = latest.cpuUsage {
            cpuHistory.append(cpu)
            if cpuHistory.count > Self.historyLength {
                cpuHistory.removeFirst(cpuHistory.count - Self.historyLength)
            }
        }

        let busiest = max(latest.networkDownBytesPerSecond ?? 0, latest.networkUpBytesPerSecond ?? 0)
        networkPeak = max(1_000_000, busiest, networkPeak * 0.98)
    }
}
