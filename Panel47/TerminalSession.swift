import AppKit
import SwiftTerm

/// One PTY-backed shell session. The `LocalProcessTerminalView` is created once
/// and kept alive for the session's lifetime — switching tabs reparents this
/// view rather than recreating it, so the shell process is never interrupted.
final class TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let terminalView: LocalProcessTerminalView

    init(number: Int, settings: AppSettings) {
        title = "Session \(number)"

        let view = LocalProcessTerminalView(frame: .zero)
        let shellPath = settings.customShellPath.isEmpty
            ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            : settings.customShellPath

        // A leading "-" in argv[0] tells the shell it's a login shell, so it
        // sources /etc/zprofile and ~/.zprofile — which is where Homebrew's
        // installer puts its PATH setup. Without this, a GUI-launched app's
        // shell only gets the bare-bones PATH the process inherited at launch.
        let loginShellName = "-" + (shellPath as NSString).lastPathComponent

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.append("TERM=xterm-256color")

        let currentDirectory = settings.workingDirectory.isEmpty ? nil : settings.workingDirectory

        view.startProcess(
            executable: shellPath,
            args: [],
            environment: environment,
            execName: loginShellName,
            currentDirectory: currentDirectory
        )
        terminalView = view

        applyAppearance(fontSize: settings.fontSize, colorScheme: settings.colorScheme)
    }

    func applyAppearance(fontSize: Double, colorScheme: TerminalColorScheme) {
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeForegroundColor = colorScheme.foreground
        terminalView.nativeBackgroundColor = colorScheme.background
    }
}
