import Foundation

/// Runs a shell command in its own background process — deliberately not the
/// visible PTY session — and streams its output line by line. This is what
/// lets quick actions show results without the user ever seeing a terminal.
final class ShellCommandRunner: ObservableObject {
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?

    private var process: Process?
    private var pendingLine = ""

    func run(_ command: String) {
        stop()

        outputLines = []
        pendingLine = ""
        exitCode = nil
        isRunning = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -l sources the login profile (same reason the terminal sessions need it:
        // that's where Homebrew's installer puts its PATH setup) without needing
        // the argv[0] "-zsh" trick, since we're not naming argv[0] here at all.
        process.arguments = ["-l", "-c", command]

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb" // discourage spinners/progress redraws meant for a real TTY
        environment["NO_COLOR"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.pendingLine.isEmpty {
                    self.outputLines.append(self.pendingLine)
                    self.pendingLine = ""
                }
                self.isRunning = false
                self.exitCode = finished.terminationStatus
            }
        }

        self.process = process
        do {
            try process.run()
        } catch {
            outputLines.append("Failed to launch: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stop() {
        let previous = process
        process = nil
        previous?.terminationHandler = nil
        if previous?.isRunning == true {
            previous?.terminate()
        }
    }

    /// Buffers partial lines across read chunks so a line split across two
    /// pipe reads doesn't render as two separate lines.
    private func appendOutput(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        pendingLine += normalized
        var segments = pendingLine.components(separatedBy: "\n")
        pendingLine = segments.removeLast()
        if !segments.isEmpty {
            outputLines.append(contentsOf: segments)
        }
    }
}
