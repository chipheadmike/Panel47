import Foundation
import Testing
@testable import Panel47

struct SudoPromptDetectorTests {
    @Test func recognizesRealSudoPromptText() {
        #expect(SudoPromptDetector.prompt(in: "Password:") == "Password:")
        #expect(SudoPromptDetector.prompt(in: "Password: ") == "Password:")
        #expect(SudoPromptDetector.prompt(in: "  Password:  ") == "Password:")
    }

    @Test func recognizesTheLinuxStyleVariant() {
        #expect(SudoPromptDetector.prompt(in: "[sudo] password for mike:") == "[sudo] password for mike:")
    }

    @Test func isCaseInsensitive() {
        #expect(SudoPromptDetector.prompt(in: "password:") != nil)
        #expect(SudoPromptDetector.prompt(in: "PASSWORD:") != nil)
    }

    @Test func ordinaryOutputThatMentionsPasswordIsNotAPrompt() {
        #expect(SudoPromptDetector.prompt(in: "Changing password file for user") == nil)
        #expect(SudoPromptDetector.prompt(in: "Password expires in 30 days") == nil)
    }

    @Test func emptyOrUnrelatedTextIsNotAPrompt() {
        #expect(SudoPromptDetector.prompt(in: "") == nil)
        #expect(SudoPromptDetector.prompt(in: "   ") == nil)
        #expect(SudoPromptDetector.prompt(in: "Downloading Docker.pkg") == nil)
    }
}

/// These run real commands through a real pseudo-terminal, so they check
/// real end-to-end behavior rather than a mock.
@MainActor
struct LivePTYCommandRunnerTests {
    private func waitUntilFinished(_ runner: PTYCommandRunner, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while runner.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // `LocalProcess` detects process exit (waitpid) and pty EOF as two
        // independent events; the last chunk of output can still be queued
        // for delivery for a moment after `isRunning` flips false. A brief
        // settle window avoids a false negative on the very last line.
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private func waitUntilPromptShown(_ runner: PTYCommandRunner, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while runner.passwordPrompt == nil && runner.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func capturesOutputFromASimpleCommand() async throws {
        let runner = PTYCommandRunner()
        runner.run("echo hello-panel47")
        try await waitUntilFinished(runner)
        #expect(runner.exitCode == 0)
        #expect(runner.outputLines.contains("hello-panel47"))
    }

    @Test func capturesNonZeroExitCode() async throws {
        let runner = PTYCommandRunner()
        runner.run("exit 3")
        try await waitUntilFinished(runner)
        #expect(runner.exitCode == 3)
    }

    @Test func startingANewRunReplacesThePreviousOne() async throws {
        let runner = PTYCommandRunner()
        runner.run("echo first")
        try await waitUntilFinished(runner)

        runner.run("echo second")
        try await waitUntilFinished(runner)
        #expect(runner.outputLines == ["second"])
    }

    /// Stands in for a real `sudo` prompt without touching `sudo` or system
    /// privileges: `read -s` reads one line with echo disabled, exactly the
    /// termios behavior a real password prompt relies on, after printing
    /// the same "Password:" text real `sudo` prints with no trailing
    /// newline — which is what makes it a prompt rather than a line of
    /// output.
    @Test func detectsAFakePromptAndDeliversTheSubmittedPassword() async throws {
        let runner = PTYCommandRunner()
        runner.run(#"printf 'Password:'; read -s reply; echo; echo "got:$reply""#)

        try await waitUntilPromptShown(runner)
        #expect(runner.passwordPrompt == "Password:")
        // The prompt text sits in the pty's pending buffer, not yet a
        // completed line, and read -s never echoes what's typed either.
        #expect(!runner.outputLines.contains { $0.contains("Password") })

        runner.submitPassword("hunter2")
        try await waitUntilFinished(runner)

        #expect(runner.passwordPrompt == nil)
        #expect(runner.outputLines.contains("got:hunter2"))
        // The password itself must never appear as its own echoed line.
        #expect(!runner.outputLines.contains("hunter2"))
    }

    @Test func submittingWithNoPendingPromptDoesNothing() async throws {
        let runner = PTYCommandRunner()
        runner.run("echo no-prompt-here")
        try await waitUntilFinished(runner)
        runner.submitPassword("shouldnt-matter") // must not crash or hang
        #expect(runner.outputLines.contains("no-prompt-here"))
    }

    @Test func stopTerminatesARunningCommand() async throws {
        let runner = PTYCommandRunner()
        runner.run("sleep 30")
        // Give the process a moment to actually start before stopping it.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(runner.isRunning)
        runner.stop()
        try await waitUntilFinished(runner, timeout: 3)
        #expect(!runner.isRunning)
    }
}
