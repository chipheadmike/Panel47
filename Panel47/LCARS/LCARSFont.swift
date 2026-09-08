import SwiftUI
import AppKit

/// Wraps the bundled Antonio variable font (OFL-licensed, see LICENSES-Antonio-OFL.txt)
/// so LCARS text can dial in a specific weight along its `wght` axis rather than being
/// stuck on whatever weight SwiftUI's default `.custom` lookup happens to resolve.
enum LCARSFont {
    private static let weightAxisTag: NSNumber = 0x77676874 // 'wght'

    static func antonio(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        let descriptor = NSFontDescriptor(name: "Antonio", size: size)
            .addingAttributes([.variation: [weightAxisTag: weight]])
        if let nsFont = NSFont(descriptor: descriptor, size: size) {
            return Font(nsFont)
        }
        return .custom("Antonio", size: size)
    }
}
