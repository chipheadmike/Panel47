import Combine
import Foundation

/// Reads `git status` for one directory. A single process with merged
/// stdout+stderr and output that's never more than a few KB, so none of the
/// multi-process pipe pitfalls in [[feedback-macos-subprocess-pipes]] apply
/// here — still uses the same `readToEnd()` pattern on principle, since it's
/// the correct one regardless of scale.
enum GitSampler {
    static func isRepository(directory: String) -> Bool {
        let result = run(directory: directory, arguments: ["rev-parse", "--is-inside-work-tree"])
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func readStatus(directory: String, completion: @escaping (GitRepoStatus?) -> Void) {
        readRaw(directory: directory, arguments: ["status", "--porcelain=v2", "--branch"]) { output in
            completion(output.map(GitStatusParser.parse))
        }
    }

    private static func readRaw(directory: String, arguments: [String], completion: @escaping (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            completion(nil)
            return
        }

        Task {
            let data = try? await pipe.fileHandleForReading.readToEnd()
            completion(data.flatMap { String(data: $0, encoding: .utf8) })
        }
    }

    /// Synchronous convenience for the one-shot repository check, which
    /// happens at panel-list build time alongside `ToolDetector`'s plain
    /// file-existence checks.
    private static func run(directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Bounded, single-line output (`true`/`false`), so a blocking read
        // after exit can't deadlock the way a chatty, concurrent scan could.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Drives one repository's Tactical panel: the status board, and the three
/// background actions (fetch, pull, stash). Actions reuse `PTYCommandRunner`
/// — the same runner BREW's actions use, with a real pty so a command that
/// needs a password (an SSH passphrase, say) can prompt for one instead of
/// just failing — rather than adding another subprocess path.
final class TacticalModel: ObservableObject {
    let directory: String

    @Published private(set) var status: GitRepoStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var notice: String?

    @Published private(set) var actionTitle: String?
    @Published private(set) var actionOutput: [String] = []
    @Published private(set) var isActionRunning = false
    @Published private(set) var passwordPrompt: String?

    private let statusReader: (String, @escaping (GitRepoStatus?) -> Void) -> Void
    private let runner: PTYCommandRunner
    private var cancellables = Set<AnyCancellable>()

    init(
        directory: String,
        statusReader: @escaping (String, @escaping (GitRepoStatus?) -> Void) -> Void = GitSampler.readStatus,
        runner: PTYCommandRunner = PTYCommandRunner()
    ) {
        self.directory = directory
        self.statusReader = statusReader
        self.runner = runner

        runner.$isRunning
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] running in
                guard let self, !running else { return }
                self.isActionRunning = false
                self.actionOutput = self.runner.outputLines
                self.refresh()
            }
            .store(in: &cancellables)

        runner.$passwordPrompt
            .receive(on: DispatchQueue.main)
            .assign(to: &$passwordPrompt)
    }

    /// Forwards to the underlying runner; see `PTYCommandRunner.submitPassword`.
    func submitPassword(_ password: String) {
        runner.submitPassword(password)
    }

    func start() {
        guard status == nil, !isRefreshing else { return }
        refresh()
    }

    func stop() {
        runner.stop()
    }

    func refresh() {
        isRefreshing = true
        statusReader(directory) { [weak self] status in
            DispatchQueue.main.async {
                self?.applyStatus(status)
            }
        }
    }

    /// Applies a status read; also called directly by tests, bypassing the
    /// `DispatchQueue.main.async` hop `refresh()` needs in production (the
    /// real reader completes on a background thread).
    func applyStatus(_ status: GitRepoStatus?) {
        isRefreshing = false
        self.status = status
        notice = status == nil ? "COULD NOT READ REPOSITORY STATUS" : nil
    }

    func fetch() { runAction("FETCH", "git -C \(quotedDirectory) fetch") }

    func pull() {
        guard status?.isClean == true else {
            notice = "PULL REFUSED \u{00B7} WORKING TREE NOT CLEAN"
            return
        }
        runAction("PULL", "git -C \(quotedDirectory) pull")
    }

    func stash() { runAction("STASH", "git -C \(quotedDirectory) stash") }

    private func runAction(_ title: String, _ command: String) {
        notice = nil
        actionTitle = title
        actionOutput = []
        isActionRunning = true
        runner.run(command)
    }

    private var quotedDirectory: String {
        "'\(directory.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
