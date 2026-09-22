import Foundation

struct CPUTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Byte counters for one network interface. The kernel's `getifaddrs` counters
/// are 32-bit, so they wrap at 4 GiB; deltas are computed with wrapping math.
struct InterfaceCounters: Equatable {
    var bytesIn: UInt32
    var bytesOut: UInt32
}

struct BatteryStatus: Equatable {
    let percent: Int
    let isCharging: Bool
    let isOnACPower: Bool
    let minutesRemaining: Int?
}

struct SystemMetrics: Equatable {
    /// nil until there are two samples to compare.
    var cpuUsage: Double?
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var diskUsedBytes: UInt64
    var diskTotalBytes: UInt64
    /// nil on Macs without a battery.
    var battery: BatteryStatus?
    var networkDownBytesPerSecond: Double?
    var networkUpBytesPerSecond: Double?
    var uptime: TimeInterval
    var thermalState: ProcessInfo.ThermalState
    var loadAverage: Double?

    var memoryFraction: Double {
        memoryTotalBytes > 0 ? min(1, Double(memoryUsedBytes) / Double(memoryTotalBytes)) : 0
    }

    var diskFraction: Double {
        diskTotalBytes > 0 ? min(1, Double(diskUsedBytes) / Double(diskTotalBytes)) : 0
    }
}

enum GaugeLevel: Equatable {
    case normal, warning, critical

    static func level(for fraction: Double, warning: Double = 0.75, critical: Double = 0.9) -> GaugeLevel {
        if fraction >= critical { return .critical }
        if fraction >= warning { return .warning }
        return .normal
    }
}

/// Pure calculations behind the readouts, kept apart from the system calls
/// so they can be tested with made-up numbers.
enum SystemMath {
    /// Fraction of CPU time spent busy between two tick snapshots, or nil if
    /// no time passed. Uses wrapping subtraction since the counters are 32-bit.
    static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        let user = Double(new.user &- old.user)
        let system = Double(new.system &- old.system)
        let nice = Double(new.nice &- old.nice)
        let idle = Double(new.idle &- old.idle)

        let busy = user + system + nice
        let total = busy + idle
        guard total > 0 else { return nil }
        return busy / total
    }

    /// Bytes moved between two snapshots, summed over interfaces present in
    /// both (an interface that appeared or vanished can't be compared).
    static func networkDelta(
        from old: [String: InterfaceCounters],
        to new: [String: InterfaceCounters]
    ) -> (bytesIn: UInt64, bytesOut: UInt64) {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for (name, current) in new {
            guard let previous = old[name] else { continue }
            bytesIn += UInt64(current.bytesIn &- previous.bytesIn)
            bytesOut += UInt64(current.bytesOut &- previous.bytesOut)
        }
        return (bytesIn, bytesOut)
    }

    static func rate(bytes: UInt64, seconds: TimeInterval) -> Double {
        seconds > 0 ? Double(bytes) / seconds : 0
    }
}

/// Conditions that put the panel into red alert.
enum SystemAlertRules {
    static func reasons(for metrics: SystemMetrics) -> [String] {
        var reasons: [String] = []

        if metrics.diskFraction >= 0.90 {
            reasons.append("STORAGE \(StatusFormat.percent(metrics.diskFraction)) FULL")
        }
        if metrics.memoryFraction >= 0.95 {
            reasons.append("MEMORY \(StatusFormat.percent(metrics.memoryFraction)) IN USE")
        }
        if let battery = metrics.battery, battery.percent <= 10, !battery.isOnACPower {
            reasons.append("POWER AT \(battery.percent)%")
        }
        switch metrics.thermalState {
        case .serious: reasons.append("THERMAL STATE SERIOUS")
        case .critical: reasons.append("THERMAL STATE CRITICAL")
        default: break
        }

        return reasons
    }
}

/// LCARS readouts are upper case.
enum StatusFormat {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Decimal units, like network speeds are quoted: 12.3 MB/S.
    static func rate(_ bytesPerSecond: Double) -> String {
        let units: [(size: Double, name: String)] = [(1e9, "GB/S"), (1e6, "MB/S"), (1e3, "KB/S")]
        for unit in units where bytesPerSecond >= unit.size {
            let value = bytesPerSecond / unit.size
            return "\(String(format: value < 10 ? "%.1f" : "%.0f", value)) \(unit.name)"
        }
        return "\(Int(bytesPerSecond.rounded())) B/S"
    }

    static func bytes(_ count: UInt64, style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(count, UInt64(Int64.max))), countStyle: style).uppercased()
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "NOMINAL"
        case .fair: return "FAIR"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        @unknown default: return "UNKNOWN"
        }
    }
}
