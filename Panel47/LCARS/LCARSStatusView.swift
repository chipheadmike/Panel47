import SwiftUI

/// Live ship's-status board: real readings from the machine, with a red-alert
/// banner when something crosses a danger threshold. Samples only while shown.
struct LCARSStatusView: View {
    @ObservedObject var model: SystemStatusModel

    @State private var pulse = false

    var body: some View {
        let metrics = model.metrics
        let alerts = SystemAlertRules.reasons(for: metrics)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SHIP STATUS")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(alerts.isEmpty ? LCARSColor.textOnBlack : LCARSColor.alertRed)

                if !alerts.isEmpty {
                    alertBanner(alerts)
                }

                gauges(metrics)
                readouts(metrics)
                cpuHistory
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(LCARSColor.background)
        .onAppear {
            model.start()
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear { model.stop() }
    }

    // MARK: - Sections

    private func alertBanner(_ reasons: [String]) -> some View {
        HStack(spacing: 14) {
            Text("RED ALERT")
                .font(LCARSFont.antonio(20, weight: 700))
                .tracking(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Capsule().fill(LCARSColor.gloss(LCARSColor.alertRed)))

            Text(reasons.joined(separator: "  \u{00B7}  "))
                .font(LCARSFont.antonio(20, weight: 400))
                .tracking(0.5)
                .foregroundStyle(LCARSColor.alertRed)
        }
        .opacity(pulse ? 1 : 0.7)
    }

    @ViewBuilder
    private func gauges(_ m: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GaugeRow(
                label: "PROCESSOR", color: LCARSColor.orange,
                fraction: m.cpuUsage,
                value: m.cpuUsage.map(StatusFormat.percent) ?? "--"
            )
            GaugeRow(
                label: "MEMORY", color: LCARSColor.periwinkle,
                fraction: m.memoryFraction,
                value: "\(StatusFormat.bytes(m.memoryUsedBytes, style: .memory)) / \(StatusFormat.bytes(m.memoryTotalBytes, style: .memory))"
            )
            GaugeRow(
                label: "STORAGE", color: LCARSColor.lilac,
                fraction: m.diskFraction,
                value: "\(StatusFormat.bytes(m.diskUsedBytes, style: .file)) / \(StatusFormat.bytes(m.diskTotalBytes, style: .file))"
            )
            powerRow(m.battery)
            GaugeRow(
                label: "DOWNLINK", color: LCARSColor.peach,
                fraction: m.networkDownBytesPerSecond.map { min(1, $0 / model.networkPeak) },
                value: m.networkDownBytesPerSecond.map(StatusFormat.rate) ?? "--",
                usesLevels: false
            )
            GaugeRow(
                label: "UPLINK", color: LCARSColor.paleCanary,
                fraction: m.networkUpBytesPerSecond.map { min(1, $0 / model.networkPeak) },
                value: m.networkUpBytesPerSecond.map(StatusFormat.rate) ?? "--",
                usesLevels: false
            )
        }
    }

    private func powerRow(_ battery: BatteryStatus?) -> some View {
        guard let battery else {
            return GaugeRow(
                label: "POWER", color: LCARSColor.iceBlue,
                fraction: nil, value: "AC POWER", usesLevels: false
            )
        }

        let state = battery.isCharging ? "CHARGING" : (battery.isOnACPower ? "AC" : "BATTERY")
        return GaugeRow(
            label: "POWER", color: LCARSColor.iceBlue,
            fraction: Double(battery.percent) / 100,
            value: "\(battery.percent)% \u{00B7} \(state)",
            // Low is the bad direction for a battery.
            levelFraction: 1 - Double(battery.percent) / 100
        )
    }

    private func readouts(_ m: SystemMetrics) -> some View {
        HStack(spacing: 36) {
            readout("UPTIME", StatusFormat.duration(m.uptime))
            readout("THERMAL", StatusFormat.thermal(m.thermalState))
            readout("LOAD", m.loadAverage.map { String(format: "%.2f", $0) } ?? "--")
        }
        .padding(.top, 4)
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(LCARSFont.antonio(12, weight: 700))
                .tracking(1.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
            Text(value)
                .font(LCARSFont.antonio(24, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
        }
    }

    private var cpuHistory: some View {
        let length = SystemStatusModel.historyLength
        let samples: [Double?] = Array(repeating: nil, count: max(0, length - model.cpuHistory.count))
            + model.cpuHistory.map { Optional($0) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("PROCESSOR HISTORY \u{00B7} LAST \(length) SECONDS")
                .font(LCARSFont.antonio(12, weight: 700))
                .tracking(1.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(samples.indices, id: \.self) { index in
                    let value = samples[index]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value == nil ? Color.white.opacity(0.06) : LCARSColor.orange)
                        .frame(height: max(3, 56 * (value ?? 0)))
                }
            }
            .frame(height: 56, alignment: .bottom)
            .animation(.easeOut(duration: 0.3), value: model.cpuHistory)
        }
        .padding(.top, 6)
    }
}

/// A label block, a segmented bar, and a value — the classic LCARS readout.
private struct GaugeRow: View {
    let label: String
    let color: Color
    let fraction: Double?
    let value: String
    var usesLevels = true
    /// Fraction used to pick the warning color, when it differs from what's drawn.
    var levelFraction: Double?

    private let segments = 40

    private var lit: Int {
        guard let fraction else { return 0 }
        return max(0, min(segments, Int((fraction * Double(segments)).rounded())))
    }

    private var level: GaugeLevel {
        guard usesLevels, let basis = levelFraction ?? fraction else { return .normal }
        return GaugeLevel.level(for: basis)
    }

    private var barColor: Color {
        switch level {
        case .normal: return color
        case .warning: return LCARSColor.paleCanary
        case .critical: return LCARSColor.alertRed
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(color))
                .frame(width: 150, height: 40)
                .overlay(alignment: .trailing) {
                    Text(label)
                        .font(LCARSFont.antonio(18, weight: 700))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.trailing, 12)
                }

            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < lit ? barColor : Color.white.opacity(0.07))
                }
            }
            .frame(height: 26)
            .animation(.easeOut(duration: 0.5), value: lit)

            Text(value)
                .font(LCARSFont.antonio(24, weight: 700))
                .foregroundStyle(level == .critical ? LCARSColor.alertRed : LCARSColor.textOnBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 210, alignment: .trailing)
        }
    }
}
