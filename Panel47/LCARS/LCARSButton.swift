import SwiftUI

/// A pill-shaped LCARS control: colored fill, black caps text — the inverse of
/// the orange-on-black convention used for body text.
struct LCARSButton: View {
    var title: String
    var color: Color = LCARSColor.orange
    var alignment: Alignment = .trailing
    var action: () -> Void = {}

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
        .background(Capsule().fill(color))
    }
}
