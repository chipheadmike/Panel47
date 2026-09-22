import Foundation
import SwiftTerm

/// Recognizes a `sudo`-style password prompt in whatever text is still
/// pending at the end of a command's output (not yet terminated by a
/// newline, since the prompt sits there waiting for input rather than
/// ending a line). Kept apart from the runner so it can be tested against
/// real prompt text without spawning a process.
enum SudoPromptDetector {
    /// macOS's default BSD `sudo` prompt is plain `Password:`; some
    /// configurations use `[sudo] password for <user>:`. Matched
    /// case-insensitively, anchored to the end of the pending text so
    /// ordinary output that happens to mention "password" well before the
    /// end doesn't false-positive.
    static func prompt(in pendingText: String) -> String? {
        let trimmed = pendingText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: #"(?i)password( for \S+)?:\s*$"#, options: .regularExpression) != nil else { return nil }
        return trimmed
    }
}

/// Decodes the raw status word `waitpid` fills in — SwiftTerm's
/// `LocalProcess` hands this straight to its delegate without decoding it,
/// which reads as a wildly wrong exit code otherwise (`exit 3` reports 768,
/// not 3: the real code sits in bits 8–15 of the raw status).
enum WaitStatus {
    /// The C `WEXITSTATUS` macro, reimplemented since it isn't callable
    /// from Swift here. Only meaningful for a normal exit; a process killed
    /// by a signal encodes the signal number in the low bits instead, which
    /// this doesn't attempt to distinguish — not a case any of this app's
    /// commands need to report specially.
    static func exitCode(fromRawStatus status: Int32) -> Int32 {
        (status >> 8) & 0xFF
    }
}

/// Runs a shell command with a real pseudo-terminal attached — using
/// SwiftTerm's `LocalProcess`, the same PTY machinery the visible terminal
/// sessions use, but headless (no view, nothing shown on screen). A plain
/// `Process` + `Pipe`, which is what `ShellCommandRunner` uses, has no
/// controlling terminal, so a command that shells out to `sudo` (Homebrew's
/// cask installers do this for privileged helpers — Docker is a common one)
/// finds no tty to prompt on and fails immediately rather than asking for a
/// password. A real pty fixes that, and lets this runner detect the prompt
/// and surface it in the panel instead of the action just failing silently.
///
/// `TERM=dumb` and `NO_COLOR=1` are kept even with a real pty: `sudo`'s
/// prompting and echo suppression work at the termios level, not by
/// interpreting `TERM`, so a well-behaved CLI tool still falls back to
/// plain-line output — this isn't a general terminal emulator, and doesn't
/// need to be one. The pty's own line discipline still turns an outgoing
/// `\n` into `\r\n` regardless of `TERM`, though (that's the kernel, not
/// the child), so output is normalized the same way `ShellCommandRunner`
/// normalizes a real terminal's line endings before splitting into lines.
final class PTYCommandRunner: NSObject, ObservableObject, LocalProcessDelegate {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?
    /// Non-nil while waiting for the user to answer a detected password
    /// prompt; the prompt text itself, shown verbatim.
    @Published private(set) var passwordPrompt: String?

    private lazy var process = LocalProcess(delegate: self, dispatchQueue: .main)
    private var pendingLine = ""

    func run(_ command: String) {
        stop()
        outputLines = []
        pendingLine = ""
        exitCode = nil
        passwordPrompt = nil
        isRunning = true

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.append("TERM=dumb")
        environment.append("NO_COLOR=1")
        environment.append("HOMEBREW_NO_COLOR=1")

        process.startProcess(executable: "/bin/zsh", args: ["-l", "-c", command], environment: environment, execName: "-zsh")
    }

    /// Sends the password, followed by a newline to submit it — exactly
    /// what typing it at a real terminal and pressing return does. Never
    /// echoed back into `outputLines`: the pty's own echo suppression
    /// (the same mechanism a real terminal relies on) keeps it out of the
    /// data this runner receives in the first place.
    func submitPassword(_ password: String) {
        guard passwordPrompt != nil else { return }
        passwordPrompt = nil
        var bytes = Array(password.utf8)
        bytes.append(0x0A)
        process.send(data: bytes[...])
    }

    /// `LocalProcess.terminate()` kills the child but — unlike a normal
    /// exit — never calls back into `processTerminated`, so this runner's
    /// own published state has to be settled here rather than waiting for
    /// a delegate callback that isn't coming.
    func stop() {
        guard isRunning else { return }
        process.terminate()
        isRunning = false
        passwordPrompt = nil
    }

    // MARK: - LocalProcessDelegate

    func dataReceived(slice: ArraySlice<UInt8>) {
        pendingLine += String(decoding: slice, as: UTF8.self)
        appendCompleteLines()

        if let prompt = SudoPromptDetector.prompt(in: pendingLine) {
            passwordPrompt = prompt
        }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        appendCompleteLines(flushRemainder: true)
        isRunning = false
        self.exitCode = exitCode.map(WaitStatus.exitCode(fromRawStatus:))
        passwordPrompt = nil
    }

    func getWindowSize() -> winsize {
        winsize(ws_row: 48, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
    }

    /// A real pty turns an outgoing `\n` into `\r\n` (and a bare `\r` is
    /// possible too, from a program doing its own carriage-return
    /// overwrites), so both are normalized to `\n` before splitting —
    /// otherwise every line would carry a trailing `\r` that doesn't belong
    /// in it.
    private func appendCompleteLines(flushRemainder: Bool = false) {
        let normalized = pendingLine.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var segments = normalized.components(separatedBy: "\n")
        pendingLine = segments.removeLast()
        if !segments.isEmpty {
            outputLines.append(contentsOf: segments)
        }
        if flushRemainder, !pendingLine.isEmpty {
            outputLines.append(pendingLine)
            pendingLine = ""
        }
    }
}
