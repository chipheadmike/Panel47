import Foundation

/// A single security check's result, independent of how it was read.
enum SecurityState: Equatable {
    case good, bad
    /// The tool couldn't answer right now — not itself a problem to report.
    case unknown
}

struct SecurityCheck: Equatable, Identifiable {
    let id: String
    let label: String
    let state: SecurityState
    let detail: String
}

/// Parses the plain-text output of the command-line security tools. Each
/// takes whatever the tool prints (which may be empty or unexpected, if the
/// tool isn't present or the command failed) and never throws.
enum SecurityParsers {
    /// `fdesetup status`
    static func fileVault(_ output: String) -> SecurityState {
        if output.contains("FileVault is On") { return .good }
        if output.contains("FileVault is Off") { return .bad }
        return .unknown
    }

    /// `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`
    static func firewall(_ output: String) -> SecurityState {
        if output.contains("enabled") { return .good }
        if output.contains("disabled") { return .bad }
        return .unknown
    }

    /// `spctl --status`
    static func gatekeeper(_ output: String) -> SecurityState {
        if output.contains("assessments enabled") { return .good }
        if output.contains("assessments disabled") { return .bad }
        return .unknown
    }

    /// `csrutil status`
    static func systemIntegrityProtection(_ output: String) -> SecurityState {
        if output.contains("status: enabled") { return .good }
        if output.contains("status: disabled") { return .bad }
        return .unknown
    }
}

/// Time Machine needs two calls: whether a destination is configured at all,
/// and (if so) when it last backed up — which can fail on its own if the
/// destination isn't currently mounted, without that meaning anything is wrong.
enum TimeMachineParser {
    /// `tmutil destinationinfo`
    static func hasDestination(_ output: String) -> Bool {
        !output.contains("No destinations configured")
    }

    /// `tmutil latestbackup`. The backup name ends in a timestamp like
    /// `2026-09-20-101500`; nil if there isn't one to parse (no backup yet,
    /// or the destination isn't reachable right now).
    static func latestBackupDate(_ output: String) -> Date? {
        guard let range = output.range(of: #"(\d{4}-\d{2}-\d{2}-\d{6})"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: String(output[range]))
    }
}

struct TimeMachineStatus: Equatable {
    var hasDestination: Bool
    var lastBackupDate: Date?
}

enum SecurityMath {
    /// A backup older than this counts as stale, not just informational.
    static let staleBackupAge: TimeInterval = 7 * 86_400

    static func timeMachineCheck(_ status: TimeMachineStatus, now: Date = Date()) -> SecurityCheck {
        guard status.hasDestination else {
            return SecurityCheck(id: "timemachine", label: "TIME MACHINE", state: .bad, detail: "NO BACKUP DESTINATION")
        }
        guard let lastBackup = status.lastBackupDate else {
            return SecurityCheck(id: "timemachine", label: "TIME MACHINE", state: .unknown, detail: "DESTINATION SET \u{00B7} NOT CURRENTLY REACHABLE")
        }
        let age = now.timeIntervalSince(lastBackup)
        let isStale = age >= staleBackupAge
        return SecurityCheck(
            id: "timemachine", label: "TIME MACHINE",
            state: isStale ? .bad : .good,
            detail: "LAST BACKUP \(StatusFormat.duration(max(0, age))) AGO"
        )
    }

    /// Every check that is not simply "good" is worth mentioning; `.unknown`
    /// is reported too (as informational), but only `.bad` is a red alert.
    static func alertReasons(_ checks: [SecurityCheck]) -> [String] {
        checks.filter { $0.state == .bad }.map { "\($0.label) \($0.detail)" }
    }
}
