import SwiftUI

/// Visual proving ground for the LCARS design tokens — not part of the app's
/// real navigation, just a canvas to check palette, font, and shapes together.
struct LCARSStyleGuide: View {
    private let swatches: [(String, Color)] = [
        ("Orange", LCARSColor.orange),
        ("Peach", LCARSColor.peach),
        ("Lilac", LCARSColor.lilac),
        ("Periwinkle", LCARSColor.periwinkle),
        ("Pale Canary", LCARSColor.paleCanary),
        ("Ice Blue", LCARSColor.iceBlue),
        ("Alert Red", LCARSColor.alertRed)
    ]

    var body: some View {
        ZStack {
            LCARSColor.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Text("PANEL 47")
                    .font(LCARSFont.antonio(52, weight: 700))
                    .foregroundStyle(LCARSColor.orange)

                HStack(spacing: 4) {
                    LCARSElbow(corner: .topLeft, armThickness: 40, outerRadius: 80)
                        .fill(LCARSColor.orange)
                        .frame(width: 180, height: 120)

                    LCARSElbow(corner: .topRight, armThickness: 40, outerRadius: 80)
                        .fill(LCARSColor.periwinkle)
                        .frame(width: 180, height: 120)
                }

                HStack(spacing: 4) {
                    LCARSElbow(corner: .bottomLeft, armThickness: 40, outerRadius: 80)
                        .fill(LCARSColor.lilac)
                        .frame(width: 180, height: 120)

                    LCARSElbow(corner: .bottomRight, armThickness: 40, outerRadius: 80)
                        .fill(LCARSColor.paleCanary)
                        .frame(width: 180, height: 120)
                }

                HStack(spacing: 10) {
                    ForEach(swatches, id: \.0) { swatch in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(swatch.1)
                                .frame(width: 72, height: 40)
                            Text(swatch.0)
                                .font(LCARSFont.antonio(12, weight: 400))
                                .foregroundStyle(.white)
                        }
                    }
                }

                VStack(alignment: .trailing, spacing: 6) {
                    LCARSButton(title: "New Session", color: LCARSColor.orange)
                    LCARSButton(title: "Split Pane", color: LCARSColor.periwinkle)
                    LCARSButton(title: "Settings", color: LCARSColor.lilac)
                }
                .frame(maxWidth: 260)
            }
            .padding(40)
        }
        .frame(minWidth: 900, minHeight: 760)
    }
}

#Preview {
    LCARSStyleGuide()
}
