import SwiftUI
import SwiftTerm

/// Bridges SwiftTerm's AppKit-based process terminal into SwiftUI.
/// This is the raw terminal engine only — LCARS chrome wraps around it later.
struct TerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.append("TERM=xterm-256color")

        view.startProcess(executable: shellPath, args: [], environment: environment, execName: shellName)

        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
