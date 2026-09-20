import Foundation
import Testing
@testable import Panel47

struct BrewOutdatedParserTests {
    private let sample = """
    {"formulae":[{"name":"git","installed_versions":["2.40.0"],"current_version":"2.41.0","pinned":false,"pinned_version":null}],\
    "casks":[{"name":"iterm2","installed_versions":"3.4.0","current_version":"3.5.0"}]}
    """

    @Test func parsesFormulaeAndCasks() {
        let packages = BrewOutdatedParser.parse(sample)
        #expect(packages == [
            OutdatedPackage(name: "git", installedVersion: "2.40.0", latestVersion: "2.41.0"),
            OutdatedPackage(name: "iterm2", installedVersion: "3.4.0", latestVersion: "3.5.0"),
        ])
    }

    @Test func joinsMultipleInstalledVersions() {
        let json = #"{"formulae":[{"name":"node","installed_versions":["20.1.0","20.2.0"],"current_version":"21.0.0"}],"casks":[]}"#
        #expect(BrewOutdatedParser.parse(json)?.first?.installedVersion == "20.1.0, 20.2.0")
    }

    @Test func sortsByNameIgnoringCase() {
        let json = #"{"formulae":[{"name":"wget","installed_versions":["1"],"current_version":"2"},{"name":"Awk","installed_versions":["1"],"current_version":"2"}],"casks":[]}"#
        #expect(BrewOutdatedParser.parse(json)?.map(\.name) == ["Awk", "wget"])
    }

    @Test func emptyListsParseToNoPackages() {
        #expect(BrewOutdatedParser.parse(#"{"formulae":[],"casks":[]}"#) == [])
    }

    @Test func toleratesMissingSections() {
        #expect(BrewOutdatedParser.parse("{}") == [])
    }

    @Test func rejectsTextThatIsNotJSON() {
        #expect(BrewOutdatedParser.parse("==> Downloading Homebrew API data") == nil)
        #expect(BrewOutdatedParser.parse("") == nil)
    }

    @Test func dropsNamesThatCouldInjectShellCommands() {
        let json = #"{"formulae":[{"name":"ok","installed_versions":["1"],"current_version":"2"},{"name":"foo;rm -rf ~","installed_versions":["1"],"current_version":"2"},{"name":"$(evil)","installed_versions":["1"],"current_version":"2"},{"name":"--force","installed_versions":["1"],"current_version":"2"}],"casks":[]}"#
        #expect(BrewOutdatedParser.parse(json)?.map(\.name) == ["ok"])
    }

    @Test func acceptsRealisticPackageNames() {
        for name in ["git", "python@3.12", "gcc-13", "homebrew/cask/iterm2", "c++filt", "node_exporter"] {
            #expect(BrewOutdatedParser.isSafePackageName(name), "\(name) should be accepted")
        }
    }

    @Test func upgradeActionRunsBrewUpgradeForThatPackage() {
        let package = OutdatedPackage(name: "git", installedVersion: "1", latestVersion: "2")
        #expect(package.upgradeAction.command == "brew upgrade git")
        #expect(package.upgradeAction.title == "Upgrade git")
    }
}

@MainActor
struct BrewOutdatedCheckerTests {
    @Test func readsPackagesFromTheCommandOutput() async throws {
        let json = #"{"formulae":[{"name":"git","installed_versions":["2.40.0"],"current_version":"2.41.0"}],"casks":[]}"#
        let checker = BrewOutdatedChecker(command: "printf '%s\\n' '\(json)'")
        checker.refresh()

        try await waitUntilDone(checker)

        #expect(checker.state == .ready([OutdatedPackage(name: "git", installedVersion: "2.40.0", latestVersion: "2.41.0")]))
    }

    @Test func nothingOutdatedIsReadyWithAnEmptyList() async throws {
        let checker = BrewOutdatedChecker(command: #"printf '%s\n' '{"formulae":[],"casks":[]}'"#)
        checker.refresh()

        try await waitUntilDone(checker)

        #expect(checker.state == .ready([]))
    }

    @Test func aFailingCommandIsReportedAsFailed() async throws {
        let checker = BrewOutdatedChecker(command: "exit 1")
        checker.refresh()

        try await waitUntilDone(checker)

        #expect(checker.state == .failed)
    }

    @Test func outputThatIsNotJSONIsReportedAsFailed() async throws {
        let checker = BrewOutdatedChecker(command: "echo not json")
        checker.refresh()

        try await waitUntilDone(checker)

        #expect(checker.state == .failed)
    }

    @Test func isCheckingWhileTheCommandRuns() {
        let checker = BrewOutdatedChecker(command: "sleep 1")
        checker.refresh()
        #expect(checker.state == .checking)
    }

    private func waitUntilDone(_ checker: BrewOutdatedChecker, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while checker.state == .checking && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
