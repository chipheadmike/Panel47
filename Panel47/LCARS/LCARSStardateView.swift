import SwiftUI

/// A small live readout next to the sidebar clock. Updates every few seconds —
/// the fractional digit only actually moves every several minutes, so there's
/// no point refreshing more often than that.
struct LCARSStardateView: View {
    @State private var value = Stardate.string()

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 2) {
            Text("STARDATE")
                .font(LCARSFont.antonio(11, weight: 700))
                .tracking(1.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
            Text(value)
                .font(LCARSFont.antonio(20, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
        }
        .onReceive(timer) { _ in
            value = Stardate.string()
        }
    }
}
