import Combine
import Foundation

/// Runs the handful of command-line tools that report the Mac's security
/// posture. Every one of these needs a subprocess (there's no Mach or
/// libproc equivalent for these settings), so all reads happen off the main
/// thread and only while the panel is shown.
enum SecuritySampler {
    static func readChecks(now: Date = Date()) -> [SecurityCheck] {
        [
            onOffCheck(id: "filevault", label: "FILEVAULT", state: SecurityParsers.fileVault(run("/usr/bin/fdesetup", ["status"]) ?? "")),
            onOffCheck(id: "firewall", label: "FIREWALL", state: SecurityParsers.firewall(run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]) ?? "")),
            onOffCheck(id: "gatekeeper", label: "GATEKEEPER", state: SecurityParsers.gatekeeper(run("/usr/sbin/spctl", ["--status"]) ?? "")),
            onOffCheck(id: "sip", label: "SYSTEM INTEGRITY", state: SecurityParsers.systemIntegrityProtection(run("/usr/bin/csrutil", ["status"]) ?? "")),
            SecurityMath.timeMachineCheck(readTimeMachineStatus(), now: now),
        ]
    }

    /// The four system checks only ever say "on" or "off"; `SecurityCheck`
    /// carries a free-text detail (for Time Machine's date), so fill it in
    /// here from the state.
    private static func onOffCheck(id: String, label: String, state: SecurityState) -> SecurityCheck {
        let detail: String
        switch state {
        case .good: detail = "ENABLED"
        case .bad: detail = "DISABLED"
        case .unknown: detail = "UNKNOWN"
        }
        return SecurityCheck(id: id, label: label, state: state, detail: detail)
    }

    static func readTimeMachineStatus() -> TimeMachineStatus {
        let hasDestination = TimeMachineParser.hasDestination(run("/usr/bin/tmutil", ["destinationinfo"]) ?? "")
        let lastBackup = hasDestination ? TimeMachineParser.latestBackupDate(run("/usr/bin/tmutil", ["latestbackup"]) ?? "") : nil
        return TimeMachineStatus(hasDestination: hasDestination, lastBackupDate: lastBackup)
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // some of these (csrutil) write their answer to stderr
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Refreshes the checks on a slow beat — none of this changes second to
/// second — and only while the panel is on screen.
final class SecurityModel: ObservableObject {
    @Published private(set) var checks: [SecurityCheck] = []
    @Published private(set) var lastUpdated: Date?

    private let reader: (Date) -> [SecurityCheck]
    private let queue = DispatchQueue(label: "panel47.security", qos: .utility)
    private var timer: Timer?

    init(reader: @escaping (Date) -> [SecurityCheck] = SecuritySampler.readChecks) {
        self.reader = reader
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let checks = self.reader(now)
            DispatchQueue.main.async {
                self.checks = checks
                self.lastUpdated = now
            }
        }
    }
}
