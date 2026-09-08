import SwiftUI

/// Displays a session's terminal view by reparenting it into a plain container,
/// rather than owning/creating it — the session (and its PTY) already exists
/// and keeps running whether or not this host is currently showing it.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession?

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let terminalView = session?.terminalView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        if terminalView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            terminalView.frame = container.bounds
            terminalView.autoresizingMask = [.width, .height]
            container.addSubview(terminalView)
        }
    }
}
