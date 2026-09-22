import Foundation
import Testing
@testable import Panel47

struct SecurityParserTests {
    @Test func fileVaultIsParsedFromRealOutput() {
        #expect(SecurityParsers.fileVault("FileVault is On.\n") == .good)
        #expect(SecurityParsers.fileVault("FileVault is Off.\n") == .bad)
        #expect(SecurityParsers.fileVault("") == .unknown)
    }

    @Test func firewallIsParsedFromRealOutput() {
        #expect(SecurityParsers.firewall("Firewall is enabled. (State = 1)\n") == .good)
        #expect(SecurityParsers.firewall("Firewall is disabled. (State = 0)\n") == .bad)
        #expect(SecurityParsers.firewall("") == .unknown)
    }

    @Test func gatekeeperIsParsedFromRealOutput() {
        #expect(SecurityParsers.gatekeeper("assessments enabled\n") == .good)
        #expect(SecurityParsers.gatekeeper("assessments disabled\n") == .bad)
        #expect(SecurityParsers.gatekeeper("") == .unknown)
    }

    @Test func systemIntegrityProtectionIsParsedFromRealOutput() {
        #expect(SecurityParsers.systemIntegrityProtection("System Integrity Protection status: enabled.\n") == .good)
        #expect(SecurityParsers.systemIntegrityProtection("System Integrity Protection status: disabled.\n") == .bad)
        #expect(SecurityParsers.systemIntegrityProtection("") == .unknown)
    }
}

struct TimeMachineParserTests {
    @Test func noDestinationIsRecognized() {
        #expect(!TimeMachineParser.hasDestination("No destinations configured.\n"))
        #expect(TimeMachineParser.hasDestination("""
        ====================================================
        Name          : MBP_TM_Backup
        Kind          : Local
        ID            : 9E2D5AA4-6CA0-4193-9E43-BF19FBB4C5AD
        """))
    }

    @Test func latestBackupDateIsParsedFromARealPath() throws {
        let output = "/Volumes/MBP_TM_Backup/Backups.backupdb/Mikes-MacBook-Pro/2026-09-20-101500\n"
        let date = try #require(TimeMachineParser.latestBackupDate(output))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(components.year == 2026 && components.month == 9 && components.day == 20)
        #expect(components.hour == 10 && components.minute == 15)
    }

    @Test func aFailedMountHasNoParsableDate() {
        let output = "Failed to mount backup destination, error: Error Domain=com.apple.backupd.ErrorDomain Code=18\n"
        #expect(TimeMachineParser.latestBackupDate(output) == nil)
        #expect(TimeMachineParser.latestBackupDate("") == nil)
    }
}

struct SecurityMathTests {
    @Test func noDestinationIsBad() {
        let check = SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: false, lastBackupDate: nil))
        #expect(check.state == .bad)
        #expect(check.detail == "NO BACKUP DESTINATION")
    }

    @Test func aDestinationWithNoReadableDateIsUnknownNotBad() {
        let check = SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: true, lastBackupDate: nil))
        #expect(check.state == .unknown)
    }

    @Test func aRecentBackupIsGood() {
        let now = Date()
        let check = SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: true, lastBackupDate: now.addingTimeInterval(-3_600)), now: now)
        #expect(check.state == .good)
        #expect(check.detail == "LAST BACKUP 1H 0M AGO")
    }

    @Test func aStaleBackupIsBad() {
        let now = Date()
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)
        let check = SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: true, lastBackupDate: eightDaysAgo), now: now)
        #expect(check.state == .bad)
    }

    @Test func exactlyAtTheStaleThresholdCountsAsStale() {
        let now = Date()
        let boundary = now.addingTimeInterval(-SecurityMath.staleBackupAge)
        #expect(SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: true, lastBackupDate: boundary), now: now).state == .bad)
        let justUnder = now.addingTimeInterval(-SecurityMath.staleBackupAge + 1)
        #expect(SecurityMath.timeMachineCheck(TimeMachineStatus(hasDestination: true, lastBackupDate: justUnder), now: now).state == .good)
    }

    @Test func alertReasonsOnlyIncludeBadChecks() {
        let checks = [
            SecurityCheck(id: "a", label: "FILEVAULT", state: .good, detail: "ENABLED"),
            SecurityCheck(id: "b", label: "FIREWALL", state: .bad, detail: "DISABLED"),
            SecurityCheck(id: "c", label: "GATEKEEPER", state: .unknown, detail: "UNKNOWN"),
        ]
        #expect(SecurityMath.alertReasons(checks) == ["FIREWALL DISABLED"])
    }

    @Test func aHealthyMachineRaisesNoAlert() {
        let checks = [
            SecurityCheck(id: "a", label: "FILEVAULT", state: .good, detail: "ENABLED"),
            SecurityCheck(id: "b", label: "FIREWALL", state: .good, detail: "ENABLED"),
        ]
        #expect(SecurityMath.alertReasons(checks).isEmpty)
    }
}

/// These run the real command-line tools on this machine, so they check
/// shape and internal consistency rather than a specific expected answer.
struct LiveSecurityTests {
    @Test func allFiveChecksAreProducedInAStableOrder() {
        let checks = SecuritySampler.readChecks()
        #expect(checks.map(\.id) == ["filevault", "firewall", "gatekeeper", "sip", "timemachine"])
        #expect(checks.allSatisfy { !$0.detail.isEmpty })
    }

    @Test func toolsThatAreActuallyPresentAnswerDefinitely() {
        // On any real Mac, fdesetup and spctl exist and give a definite answer.
        let checks = SecuritySampler.readChecks()
        #expect(checks.first { $0.id == "filevault" }?.state != .unknown)
        #expect(checks.first { $0.id == "gatekeeper" }?.state != .unknown)
    }

    @Test func timeMachineDestinationInfoIsInternallyConsistent() {
        let status = SecuritySampler.readTimeMachineStatus()
        if !status.hasDestination { #expect(status.lastBackupDate == nil) }
    }
}
