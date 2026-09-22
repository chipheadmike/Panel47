import Combine
import Darwin
import Foundation

/// Reads per-process CPU time and memory from libproc. Without root, the
/// kernel only answers for processes owned by the current user, so that is
/// the list this produces.
enum ProcessSampler {
    static func readProcesses() -> [ProcessReading] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<pid_t>.size + 64)
        let bytesFilled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytesFilled > 0 else { return [] }

        let count = Int(bytesFilled) / MemoryLayout<pid_t>.size
        var readings: [ProcessReading] = []
        readings.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            if let reading = read(pid: pid) { readings.append(reading) }
        }
        return readings
    }

    static func read(pid: pid_t) -> ProcessReading? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }

        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = String(cString: nameBuffer)

        return ProcessReading(
            pid: pid,
            name: name.isEmpty ? "PID \(pid)" : name,
            uid: info.pbi_uid,
            cpuTimeNanos: nanoseconds(fromMachTime: usage.ri_user_time &+ usage.ri_system_time),
            footprintBytes: usage.ri_phys_footprint
        )
    }

    /// CPU times come back in Mach absolute time, which on Apple Silicon is
    /// not nanoseconds.
    static func nanoseconds(fromMachTime ticks: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.denom > 0 else { return ticks }
        let numer = UInt64(timebase.numer)
        let denom = UInt64(timebase.denom)
        // Split so a large tick count can't overflow the multiplication.
        return (ticks / denom) * numer + (ticks % denom) * numer / denom
    }
}

/// Refreshes the process list once a second while the panel is on screen, and
/// handles the arm-then-confirm dance for terminating a process.
final class ProcessListModel: ObservableObject {
    static let defaultRowLimit = 10

    @Published private(set) var rows: [ProcessEntry] = []
    @Published private(set) var sort: ProcessSort = .cpu
    /// The process whose TERMINATE button has been pressed once.
    @Published private(set) var armedPID: Int32?
    @Published private(set) var notice: String?

    private let reader: () -> [ProcessReading]
    private let signaler: (Int32, Int32) -> Int32
    private let ownUID: UInt32
    private let ownPID: Int32
    private let rowLimit: Int

    private var entries: [ProcessEntry] = []
    private var lastReadings: [Int32: ProcessReading] = [:]
    private var lastTime: Date?
    private var timer: Timer?

    init(
        reader: @escaping () -> [ProcessReading] = ProcessSampler.readProcesses,
        signaler: @escaping (Int32, Int32) -> Int32 = { kill($0, $1) },
        ownUID: UInt32 = getuid(),
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        rowLimit: Int = ProcessListModel.defaultRowLimit
    ) {
        self.rowLimit = rowLimit
        self.reader = reader
        self.signaler = signaler
        self.ownUID = ownUID
        self.ownPID = ownPID
    }

    func start() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        armedPID = nil
    }

    func refresh(now: Date = Date()) {
        let readings = reader()
        let wall = lastTime.map { now.timeIntervalSince($0) } ?? 0
        entries = ProcessMath.entries(
            current: readings,
            previous: lastReadings,
            wallSeconds: wall,
            ownUID: ownUID,
            ownPID: ownPID
        )
        lastReadings = Dictionary(readings.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        lastTime = now
        rank()
    }

    func setSort(_ newSort: ProcessSort) {
        sort = newSort
        rank()
    }

    private func rank() {
        rows = ProcessMath.top(entries, by: sort, limit: rowLimit)
        // The armed process left the list (quit, or fell out of the top ten).
        if let armed = armedPID, !rows.contains(where: { $0.pid == armed }) {
            armedPID = nil
        }
    }

    // MARK: - Termination

    func arm(_ pid: Int32) {
        guard rows.first(where: { $0.pid == pid })?.canTerminate == true else { return }
        notice = nil
        armedPID = pid
    }

    func cancel() {
        armedPID = nil
    }

    /// Sends SIGTERM — a polite request to quit — to the armed process.
    func confirmTerminate(_ pid: Int32) {
        guard armedPID == pid,
              let entry = rows.first(where: { $0.pid == pid }),
              entry.canTerminate else { return }
        armedPID = nil

        let result = signaler(pid, SIGTERM)
        let failure = errno
        if result == 0 {
            notice = "TERMINATION SIGNAL SENT TO \(entry.name.uppercased())"
        } else {
            notice = "COULD NOT TERMINATE \(entry.name.uppercased()): \(String(cString: strerror(failure)).uppercased())"
        }
    }
}
