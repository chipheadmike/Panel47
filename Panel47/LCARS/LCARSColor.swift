import SwiftUI

/// The classic LCARS palette — flat, high-saturation blocks on black.
enum LCARSColor {
    static let background = Color.black

    static let orange = Color(hex: 0xFF9900)
    static let peach = Color(hex: 0xFFCC99)
    static let lilac = Color(hex: 0xCC99CC)
    static let periwinkle = Color(hex: 0x9999CC)
    static let paleCanary = Color(hex: 0xFFFF99)
    static let iceBlue = Color(hex: 0x99CCFF)
    static let alertRed = Color(hex: 0xCC6666)

    /// Body/label text on black is orange in the classic scheme.
    static let textOnBlack = orange
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
