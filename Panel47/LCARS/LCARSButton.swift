import SwiftUI

/// A pill-shaped LCARS control: colored fill, black caps text — the inverse of
/// the orange-on-black convention used for body text.
struct LCARSButton: View {
    var title: String
    var color: Color = LCARSColor.orange
    var alignment: Alignment = .trailing
    /// Slowly breathes the fill's brightness — for the "this one is active" button.
    var pulses = false
    var action: () -> Void = {}

    @State private var pulseHigh = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(LCARSFont.antonio(18, weight: 700))
                .tracking(1)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(LCARSColor.gloss(color))
                .brightness(pulses && !reduceMotion ? (pulseHigh ? 0.12 : -0.22) : 0)
        )
        .onChange(of: pulses, initial: true) { _, isPulsing in
            if isPulsing && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulseHigh = true }
            } else {
                withAnimation(.default) { pulseHigh = false }
            }
        }
    }
}
