import Combine
import Foundation

struct OutdatedPackage: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let installedVersion: String
    let latestVersion: String

    var upgradeAction: CommandAction {
        CommandAction(title: "Upgrade \(name)", command: "brew upgrade \(name)")
    }
}

/// Parses `brew outdated --json=v2`. The JSON form is used because plain output
/// mixes in progress lines ("==> Downloading Homebrew API data"), and it keeps
/// working if the human-readable format shifts.
enum BrewOutdatedParser {
    /// Returns nil if the text isn't valid brew JSON.
    static func parse(_ output: String) -> [OutdatedPackage]? {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        return ((payload.formulae ?? []) + (payload.casks ?? []))
            .filter { isSafePackageName($0.name) }
            .map {
                OutdatedPackage(
                    name: $0.name,
                    installedVersion: $0.installedVersions.joined(separator: ", "),
                    latestVersion: $0.currentVersion ?? ""
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Names end up in a shell command (`brew upgrade <name>`), so only accept
    /// what Homebrew names can legitimately contain.
    static func isSafePackageName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[A-Za-z0-9][A-Za-z0-9@+._\/-]*/#) != nil
    }

    private struct Payload: Decodable {
        var formulae: [Entry]?
        var casks: [Entry]?
    }

    private struct Entry: Decodable {
        let name: String
        let installedVersions: [String]
        let currentVersion: String?

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            currentVersion = try? container.decodeIfPresent(String.self, forKey: .currentVersion)

            // Formulae report a list of versions; casks have reported a single string.
            if let list = try? container.decode([String].self, forKey: .installedVersions) {
                installedVersions = list
            } else if let single = try? container.decode(String.self, forKey: .installedVersions) {
                installedVersions = [single]
            } else {
                installedVersions = []
            }
        }
    }
}

/// Runs `brew outdated` in the background and publishes what it finds, so the
/// BREW panel can offer one upgrade button per outdated package.
final class BrewOutdatedChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case ready([OutdatedPackage])
        case failed
    }

    @Published private(set) var state: State = .idle

    private let command: String
    private let runner = ShellCommandRunner()
    private var cancellable: AnyCancellable?

    /// stderr is dropped so progress chatter can't corrupt the JSON on stdout.
    init(command: String = "brew outdated --json=v2 2>/dev/null") {
        self.command = command
        cancellable = runner.$exitCode
            .compactMap { $0 }
            .sink { [weak self] code in self?.finish(exitCode: code) }
    }

    func refresh() {
        state = .checking
        runner.run(command)
    }

    private func finish(exitCode: Int32) {
        guard exitCode == 0,
              let packages = BrewOutdatedParser.parse(runner.outputLines.joined(separator: "\n")) else {
            state = .failed
            return
        }
        state = .ready(packages)
    }
}
