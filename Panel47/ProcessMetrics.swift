import Foundation

/// One raw reading of a process, straight from the kernel.
struct ProcessReading: Equatable {
    let pid: Int32
    let name: String
    let uid: UInt32
    /// Total user + system CPU time consumed so far, in nanoseconds.
    let cpuTimeNanos: UInt64
    /// Memory footprint — the number Activity Monitor calls "Memory".
    let footprintBytes: UInt64
}

/// A process ready to display.
struct ProcessEntry: Equatable, Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    /// Share of one core, so a process using two cores reads 200%. nil until
    /// there are two readings to compare.
    let cpuPercent: Double?
    let footprintBytes: UInt64
    let canTerminate: Bool
}

enum ProcessSort: Equatable, CaseIterable {
    case cpu, memory
}

enum ProcessMath {
    /// CPU used between two readings, as a percentage of one core. Returns nil
    /// when the counter went backwards, which means the pid was reused by a
    /// different process.
    static func cpuPercent(previousNanos: UInt64, currentNanos: UInt64, wallSeconds: TimeInterval) -> Double? {
        guard wallSeconds > 0, currentNanos >= previousNanos else { return nil }
        return Double(currentNanos - previousNanos) / (wallSeconds * 1_000_000_000) * 100
    }

    /// Turns two consecutive readings into displayable entries.
    static func entries(
        current: [ProcessReading],
        previous: [Int32: ProcessReading],
        wallSeconds: TimeInterval,
        ownUID: UInt32,
        ownPID: Int32
    ) -> [ProcessEntry] {
        current.map { reading in
            var cpu: Double?
            // A different name under the same pid is a reused pid, not the same process.
            if let before = previous[reading.pid], before.name == reading.name {
                cpu = cpuPercent(
                    previousNanos: before.cpuTimeNanos,
                    currentNanos: reading.cpuTimeNanos,
                    wallSeconds: wallSeconds
                )
            }
            return ProcessEntry(
                pid: reading.pid,
                name: reading.name,
                cpuPercent: cpu,
                footprintBytes: reading.footprintBytes,
                canTerminate: TerminationRules.canTerminate(pid: reading.pid, uid: reading.uid, ownUID: ownUID, ownPID: ownPID)
            )
        }
    }

    /// The busiest entries first. Entries without a CPU figure yet sort last.
    static func top(_ entries: [ProcessEntry], by sort: ProcessSort, limit: Int) -> [ProcessEntry] {
        let ranked = entries.sorted { a, b in
            switch sort {
            case .cpu:
                let (x, y) = (a.cpuPercent ?? -1, b.cpuPercent ?? -1)
                if x != y { return x > y }
                if a.footprintBytes != b.footprintBytes { return a.footprintBytes > b.footprintBytes }
            case .memory:
                if a.footprintBytes != b.footprintBytes { return a.footprintBytes > b.footprintBytes }
                let (x, y) = (a.cpuPercent ?? -1, b.cpuPercent ?? -1)
                if x != y { return x > y }
            }
            return a.pid < b.pid
        }
        return Array(ranked.prefix(limit))
    }
}

enum TerminationRules {
    /// Only your own processes, never launchd (pid 1), the kernel (pid 0), or Panel 47 itself.
    static func canTerminate(pid: Int32, uid: UInt32, ownUID: UInt32, ownPID: Int32) -> Bool {
        pid > 1 && pid != ownPID && uid == ownUID
    }
}
