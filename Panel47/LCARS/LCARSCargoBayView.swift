import SwiftUI

/// Storage browser: the largest immediate subfolders of wherever you are,
/// drilled into one level at a time. A scan can take a while on a big home
/// directory, so folders appear as `du` finds them rather than all at once.
struct LCARSCargoBayView: View {
    @ObservedObject var model: CargoModel
    let playBlip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("CARGO BAY")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                pathReadout
                progress
                rows

                if model.hadSkippedItems {
                    Text("SOME ITEMS SKIPPED \u{00B7} PROTECTED BY THE SYSTEM")
                        .font(LCARSFont.antonio(12, weight: 700))
                        .tracking(1.5)
                        .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .background(LCARSColor.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var pathReadout: some View {
        Text(model.displayPath)
            .font(LCARSFont.antonio(22, weight: 700))
            .foregroundStyle(LCARSColor.textOnBlack)
            .lineLimit(1)
            .truncationMode(.head)
    }

    @ViewBuilder
    private var progress: some View {
        if model.isScanning || !model.entries.isEmpty {
            let count = model.entries.count
            let total = CargoMath.totalBytes(model.entries)
            Text(model.isScanning
                ? "SCANNING \u{00B7} \(count) FOUND SO FAR \u{00B7} \(StatusFormat.bytes(total, style: .file)) SO FAR"
                : "\(count) FOLDER\(count == 1 ? "" : "S") \u{00B7} \(StatusFormat.bytes(total, style: .file)) SHOWN")
                .font(LCARSFont.antonio(14, weight: 700))
                .tracking(1)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
        }
    }

    @ViewBuilder
    private var rows: some View {
        let top = CargoMath.top(model.entries, limit: CargoModel.rowLimit)
        let scale = max(1, top.first?.bytes ?? 0)

        if top.isEmpty && !model.isScanning {
            Text("NOTHING FOUND HERE")
                .font(LCARSFont.antonio(18, weight: 400))
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
        }

        VStack(alignment: .leading, spacing: 8) {
            ForEach(top) { entry in
                CargoRowView(
                    entry: entry,
                    fraction: CargoMath.fraction(for: entry, scale: scale),
                    onOpen: { playBlip(); model.open(entry) }
                )
            }
        }
    }

}

/// Navigation and rescan controls shown in the sidebar in place of the main
/// menu while Cargo Bay has taken over the screen.
struct CargoBaySidebarControls: View {
    @ObservedObject var model: CargoModel
    let playBlip: () -> Void

    var body: some View {
        Group {
            if model.canGoUp {
                sidebarButton("Up", LCARSColor.periwinkle) { model.goUp() }
            }
            sidebarButton(model.isScanning ? "Scanning" : "Rescan", model.isScanning ? LCARSColor.peach : LCARSColor.paleCanary) {
                if !model.isScanning { model.rescan() }
            }
        }
    }

    private func sidebarButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        LCARSButton(title: title, color: color) {
            playBlip()
            action()
        }
    }
}

private struct CargoRowView: View {
    let entry: CargoEntry
    let fraction: Double
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(LCARSColor.orange))
                .frame(width: 220, height: 40)
                .overlay(alignment: .trailing) {
                    Text(entry.name.uppercased())
                        .font(LCARSFont.antonio(18, weight: 700))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 22)
                        .padding(.trailing, 12)
                }

            LCARSSegmentBar(fraction: fraction, color: LCARSColor.lilac)

            Text(StatusFormat.bytes(entry.bytes, style: .file))
                .font(LCARSFont.antonio(20, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)

            Button(action: onOpen) {
                Text("OPEN")
                    .font(LCARSFont.antonio(15, weight: 700))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(LCARSColor.gloss(LCARSColor.iceBlue)))
            .frame(width: 90, alignment: .trailing)
        }
    }
}
