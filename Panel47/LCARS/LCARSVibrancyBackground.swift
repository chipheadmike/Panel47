import AppKit
import SwiftUI

/// A dark vibrancy material behind the whole frame — the flat black content
/// mostly hides it, but it gives the thin gutters between panels a bit of
/// depth instead of reading as pure flat paint.
struct LCARSVibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
