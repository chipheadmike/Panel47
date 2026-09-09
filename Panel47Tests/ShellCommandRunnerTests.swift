import Foundation
import Testing
@testable import Panel47

@MainActor
struct ShellCommandRunnerTests {
    @Test func capturesOutputFromASimpleCommand() async throws {
        let runner = ShellCommandRunner()
        runner.run("echo hello-panel47")

        try await waitUntilFinished(runner)

        #expect(runner.exitCode == 0)
        #expect(runner.outputLines.contains("hello-panel47"))
    }

    @Test func capturesNonZeroExitCode() async throws {
        let runner = ShellCommandRunner()
        runner.run("exit 3")

        try await waitUntilFinished(runner)

        #expect(runner.exitCode == 3)
    }

    @Test func capturesMultipleLinesInOrder() async throws {
        let runner = ShellCommandRunner()
        runner.run("printf 'one\\ntwo\\nthree\\n'")

        try await waitUntilFinished(runner)

        #expect(runner.outputLines == ["one", "two", "three"])
    }

    @Test func startingANewRunReplacesThePreviousOne() async throws {
        let runner = ShellCommandRunner()
        runner.run("echo first")
        try await waitUntilFinished(runner)

        runner.run("echo second")
        try await waitUntilFinished(runner)

        #expect(runner.outputLines == ["second"])
    }

    private func waitUntilFinished(_ runner: ShellCommandRunner, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while runner.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
