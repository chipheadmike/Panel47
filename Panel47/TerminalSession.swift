import AppKit
import SwiftTerm

/// One PTY-backed shell session. The `LocalProcessTerminalView` is created once
/// and kept alive for the session's lifetime — switching tabs reparents this
/// view rather than recreating it, so the shell process is never interrupted.
final class TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let terminalView: LocalProcessTerminalView

    init(number: Int) {
        title = "Session \(number)"

        let view = LocalProcessTerminalView(frame: .zero)
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.append("TERM=xterm-256color")

        view.startProcess(executable: shellPath, args: [], environment: environment, execName: shellName)
        terminalView = view
    }
}
