import SwiftUI

/// The real window chrome: a swept corner over a button sidebar on the left,
/// thin title/status bars top and bottom, with arbitrary content (the terminal)
/// filling the black frame in between.
struct LCARSChrome<Content: View>: View {
    private let sidebarWidth: CGFloat = 180
    private let barHeight: CGFloat = 36
    private let elbowHeight: CGFloat = 96
    private let gutter: CGFloat = 4

    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Clears the traffic lights from the hidden title bar.
            Color.clear.frame(height: 28)

            HStack(alignment: .top, spacing: gutter) {
                sidebar
                    .frame(width: sidebarWidth)

                VStack(spacing: gutter) {
                    titleBar

                    content()
                        .background(LCARSColor.background)
                        .frame(maxHeight: .infinity)

                    statusBar
                }
            }
        }
        .padding(gutter)
        .background(LCARSColor.background)
    }

    private var sidebar: some View {
        VStack(spacing: gutter) {
            LCARSElbow(corner: .topLeft, armThickness: barHeight, outerRadius: 64)
                .fill(LCARSColor.orange)
                .frame(height: elbowHeight)

            LCARSButton(title: "New Session", color: LCARSColor.orange)
            LCARSButton(title: "Split Pane", color: LCARSColor.periwinkle)
            LCARSButton(title: "Settings", color: LCARSColor.lilac)

            Spacer(minLength: 8)

            Text(Date(), style: .time)
                .font(LCARSFont.antonio(22, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

            LCARSElbow(corner: .bottomLeft, armThickness: barHeight, outerRadius: 64)
                .fill(LCARSColor.peach)
                .frame(height: elbowHeight)
        }
    }

    private var titleBar: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: barHeight / 2)
            .fill(LCARSColor.orange)
            .frame(height: barHeight)
            .overlay(alignment: .trailing) {
                Text("PANEL 47 \u{00B7} TERMINAL")
                    .font(LCARSFont.antonio(18, weight: 700))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.trailing, 24)
            }
    }

    private var statusBar: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: barHeight / 2, topTrailingRadius: 0)
            .fill(LCARSColor.peach)
            .frame(height: barHeight)
    }
}
