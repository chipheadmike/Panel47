import SwiftUI

/// The busiest processes on the ship, live, with a two-step terminate control.
/// Refreshes only while shown.
struct LCARSEngineeringView: View {
    @ObservedObject var model: ProcessListModel
    let playBlip: () -> Void

    var body: some View {
        let rows = model.rows
        let scale = barScale(rows)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ENGINEERING")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                if let notice = model.notice {
                    Text(notice)
                        .font(LCARSFont.antonio(18, weight: 400))
                        .tracking(0.5)
                        .foregroundStyle(LCARSColor.paleCanary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { entry in
                        ProcessRowView(
                            entry: entry,
                            sort: model.sort,
                            fraction: fraction(for: entry, scale: scale),
                            isArmed: model.armedPID == entry.pid,
                            onArm: { playBlip(); model.arm(entry.pid) },
                            onConfirm: { playBlip(); model.confirmTerminate(entry.pid) },
                            onCancel: { playBlip(); model.cancel() }
                        )
                    }
                }

                Text("YOUR PROCESSES ONLY \u{00B7} CPU IS SHARE OF ONE CORE \u{00B7} TERMINATE SENDS A REQUEST TO QUIT")
                    .font(LCARSFont.antonio(12, weight: 700))
                    .tracking(1.5)
                    .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .background(LCARSColor.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// Bars are relative to the busiest row so differences stay visible. CPU
    /// never scales below one full core, so an idle list doesn't look busy.
    private func barScale(_ rows: [ProcessEntry]) -> Double {
        switch model.sort {
        case .cpu:
            return max(100, rows.compactMap(\.cpuPercent).max() ?? 0)
        case .memory:
            return max(1, Double(rows.map(\.footprintBytes).max() ?? 0))
        }
    }

    private func fraction(for entry: ProcessEntry, scale: Double) -> Double? {
        switch model.sort {
        case .cpu: return entry.cpuPercent.map { min(1, $0 / scale) }
        case .memory: return min(1, Double(entry.footprintBytes) / scale)
        }
    }
}

/// Sort-order controls shown in the sidebar in place of the main menu while
/// Engineering has taken over the screen.
struct EngineeringSidebarControls: View {
    @ObservedObject var model: ProcessListModel
    let playBlip: () -> Void

    var body: some View {
        Group {
            sortButton("Processor", .cpu)
            sortButton("Memory", .memory)
        }
    }

    private func sortButton(_ title: String, _ value: ProcessSort) -> some View {
        LCARSButton(title: title, color: model.sort == value ? LCARSColor.paleCanary : LCARSColor.peach) {
            playBlip()
            model.setSort(value)
        }
    }
}

private struct ProcessRowView: View {
    let entry: ProcessEntry
    let sort: ProcessSort
    let fraction: Double?
    let isArmed: Bool
    let onArm: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let segments = 30

    private var lit: Int {
        guard let fraction else { return 0 }
        return max(0, min(segments, Int((fraction * Double(segments)).rounded())))
    }

    private var cpuText: String { entry.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "--" }
    private var memoryText: String { StatusFormat.bytes(entry.footprintBytes, style: .memory) }

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(isArmed ? LCARSColor.alertRed : LCARSColor.orange))
                .frame(width: 190, height: 40)
                .overlay(alignment: .trailing) {
                    Text(entry.name.uppercased())
                        .font(LCARSFont.antonio(16, weight: 700))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 22)
                        .padding(.trailing, 12)
                }

            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < lit ? (isArmed ? LCARSColor.alertRed : LCARSColor.periwinkle) : Color.white.opacity(0.07))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)

            VStack(alignment: .trailing, spacing: 0) {
                Text(sort == .cpu ? cpuText : memoryText)
                    .font(LCARSFont.antonio(22, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)
                Text(sort == .cpu ? memoryText : "CPU \(cpuText)")
                    .font(LCARSFont.antonio(12, weight: 700))
                    .tracking(1)
                    .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
            }
            .lineLimit(1)
            .frame(width: 100, alignment: .trailing)

            // Always reserve the button column so every bar is the same length.
            ZStack(alignment: .trailing) {
                Color.clear
                controls
            }
            .frame(width: 210, height: 40)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isArmed {
            HStack(spacing: 6) {
                pill("CONFIRM", LCARSColor.alertRed, onConfirm)
                pill("CANCEL", LCARSColor.peach, onCancel)
            }
        } else if entry.canTerminate {
            pill("TERMINATE", LCARSColor.iceBlue, onArm)
        }
    }

    private func pill(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LCARSFont.antonio(15, weight: 700))
                .tracking(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(LCARSColor.gloss(color)))
    }
}
