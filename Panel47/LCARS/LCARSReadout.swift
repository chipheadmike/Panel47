import SwiftUI

/// A cosmetic, periodically-reshuffled alphanumeric code — the kind of "the
/// system is alive" set dressing real LCARS panels print on their bars.
/// Purely decorative; bound to nothing.
struct LCARSReadout: View {
    @State private var code = LCARSReadout.randomCode()

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(code)
            .font(LCARSFont.antonio(14, weight: 600))
            .tracking(1)
            .foregroundStyle(.black.opacity(0.55))
            .onReceive(timer) { _ in
                code = Self.randomCode()
            }
    }

    private static func randomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let l1 = letters.randomElement()!
        let l2 = letters.randomElement()!
        let n1 = Int.random(in: 10...99)
        let n2 = Int.random(in: 100...999)
        return "\(l1)\(l2)-\(n1)-\(n2)"
    }
}
