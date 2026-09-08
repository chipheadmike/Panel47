import SwiftUI

/// The real window chrome: a swept corner over a button sidebar on the left,
/// thin title/status bars top and bottom, with the active session(s) filling
/// the black frame in between.
struct LCARSChrome: View {
    @ObservedObject var store: TerminalSessionStore

    private let sidebarWidth: CGFloat = 180
    private let barHeight: CGFloat = 36
    private let elbowHeight: CGFloat = 96
    private let gutter: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            // Clears the traffic lights from the hidden title bar.
            Color.clear.frame(height: 28)

            HStack(alignment: .top, spacing: gutter) {
                sidebar
                    .frame(width: sidebarWidth)

                VStack(spacing: gutter) {
                    titleBar

                    terminalArea
                        .frame(maxHeight: .infinity)

                    statusBar
                }
            }
        }
        .padding(gutter)
        .background(LCARSColor.background)
    }

    @ViewBuilder
    private var terminalArea: some View {
        if store.isSplit {
            HStack(spacing: gutter) {
                TerminalHost(session: store.session(for: store.primaryID))
                TerminalHost(session: store.session(for: store.secondaryID))
            }
            .background(LCARSColor.background)
        } else {
            TerminalHost(session: store.session(for: store.primaryID))
                .background(LCARSColor.background)
        }
    }

    private var sidebar: some View {
        VStack(spacing: gutter) {
            LCARSElbow(corner: .topLeft, armThickness: barHeight, outerRadius: 64)
                .fill(LCARSColor.orange)
                .frame(height: elbowHeight)

            LCARSButton(title: "New Session", color: LCARSColor.orange) {
                store.newSession()
            }
            LCARSButton(title: store.isSplit ? "Unsplit" : "Split Pane", color: LCARSColor.periwinkle) {
                store.toggleSplit()
            }
            LCARSButton(title: "Settings", color: LCARSColor.lilac) {}

            sessionList

            Spacer(minLength: 8)

            Text(Date(), style: .time)
                .font(LCARSFont.antonio(22, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

            LCARSElbow(corner: .bottomLeft, armThickness: barHeight, outerRadius: 64)
                .fill(LCARSColor.peach)
                .frame(height: elbowHeight)
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: gutter) {
                ForEach(store.sessions) { session in
                    LCARSButton(
                        title: session.title,
                        color: session.id == store.primaryID ? LCARSColor.paleCanary : LCARSColor.iceBlue
                    ) {
                        store.select(session.id)
                    }
                    .contextMenu {
                        Button("Close Session", role: .destructive) {
                            store.close(session.id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 220)
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
