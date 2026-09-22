import SwiftUI

/// Network board: link details, live latency, and every TCP port your
/// processes are listening on, each with a two-step terminate control.
/// Pings and scans only while shown.
struct LCARSCommsView: View {
    @ObservedObject var model: CommsModel

    var body: some View {
        let stats = LatencyStats(samples: model.latencyHistory)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("COMMUNICATIONS")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                linkReadouts(model.link)
                latency(stats)
                portsSection

                Text("YOUR PROCESSES ONLY \u{00B7} LATENCY IS A LIVE PING TO THE HOST SHOWN \u{00B7} TERMINATE SENDS A REQUEST TO QUIT")
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

    // MARK: - Link

    private func linkReadouts(_ link: LinkInfo) -> some View {
        HStack(alignment: .top, spacing: 36) {
            readout("LINK", link.interface.map { "\(link.isWiFi ? "WI-FI" : "WIRED") \($0.uppercased())" } ?? "OFFLINE")
            readout("ADDRESS", link.address ?? "--")
            readout("GATEWAY", link.gateway ?? "--")
            if let dBm = link.signalDBm {
                readout("SIGNAL", "\(dBm) DBM \u{00B7} \(SignalQuality.label(dBm: dBm))")
            }
            if let rate = link.linkRateMbps {
                readout("LINK RATE", "\(Int(rate.rounded())) MBPS")
            }
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            caption(label)
            Text(value)
                .font(LCARSFont.antonio(24, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LCARSFont.antonio(12, weight: 700))
            .tracking(1.5)
            .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
    }

    // MARK: - Latency

    private let latencyFullScale = 100.0

    private func latency(_ stats: LatencyStats) -> some View {
        let level = stats.last.map(LatencyLevel.level(forMilliseconds:)) ?? .normal
        let color: Color = level == .critical ? LCARSColor.alertRed : (level == .warning ? LCARSColor.paleCanary : LCARSColor.periwinkle)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                caption("PING")
                    .padding(.trailing, 4)
                ForEach(PingTarget.allCases, id: \.self) { target in
                    targetButton(target)
                }
            }

            HStack(spacing: 10) {
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(LCARSColor.gloss(LCARSColor.peach))
                    .frame(width: 150, height: 40)
                    .overlay(alignment: .trailing) {
                        Text("LATENCY")
                            .font(LCARSFont.antonio(18, weight: 700))
                            .tracking(1)
                            .foregroundStyle(.black)
                            .padding(.trailing, 12)
                    }

                LCARSSegmentBar(fraction: stats.last.map { min(1, $0 / latencyFullScale) }, color: color)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(stats.last.map { "\(Int($0.rounded())) MS" } ?? (model.latencyHistory.isEmpty ? "--" : "LOST"))
                        .font(LCARSFont.antonio(24, weight: 700))
                        .foregroundStyle(level == .critical ? LCARSColor.alertRed : LCARSColor.textOnBlack)
                    Text(summary(stats))
                        .font(LCARSFont.antonio(12, weight: 700))
                        .tracking(1)
                        .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
                }
                .lineLimit(1)
                .frame(width: 210, alignment: .trailing)
            }

            latencyHistory
        }
    }

    private func summary(_ stats: LatencyStats) -> String {
        guard let average = stats.average else { return model.latencyHistory.isEmpty ? "WAITING" : "NO REPLY" }
        return "AVG \(Int(average.rounded())) MS \u{00B7} LOSS \(Int((stats.lossFraction * 100).rounded()))%"
    }

    private var latencyHistory: some View {
        let length = CommsModel.historyLength
        let padding = max(0, length - model.latencyHistory.count)
        // Scale to the recent peak so ordinary jitter stays visible, never below 50 ms.
        let scale = max(50, model.latencyHistory.compactMap { $0 }.max() ?? 0)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<length, id: \.self) { index in
                let position = index - padding
                if position < 0 {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 3)
                } else if let value = model.latencyHistory[position] {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LCARSColor.peach)
                        .frame(height: max(3, 40 * min(1, value / scale)))
                } else {
                    // A lost packet: a full-height red tick.
                    RoundedRectangle(cornerRadius: 2).fill(LCARSColor.alertRed).frame(height: 40)
                }
            }
        }
        .frame(height: 40, alignment: .bottom)
    }

    private func targetButton(_ target: PingTarget) -> some View {
        Button { model.setTarget(target) } label: {
            Text(target.title)
                .font(LCARSFont.antonio(16, weight: 700))
                .tracking(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(LCARSColor.gloss(model.target == target ? LCARSColor.paleCanary : LCARSColor.periwinkle)))
    }

    // MARK: - Ports

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("LISTENING PORTS \u{00B7} TCP \u{00B7} \(model.ports.count)")
                .padding(.top, 6)

            if let notice = model.notice {
                Text(notice)
                    .font(LCARSFont.antonio(18, weight: 400))
                    .tracking(0.5)
                    .foregroundStyle(LCARSColor.paleCanary)
            }

            if model.ports.isEmpty {
                Text("NOTHING OF YOURS IS LISTENING")
                    .font(LCARSFont.antonio(18, weight: 400))
                    .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
            }

            ForEach(model.ports) { port in
                PortRowView(
                    port: port,
                    isArmed: model.armedID == port.id,
                    onArm: { model.arm(port.id) },
                    onConfirm: { model.confirmTerminate(port.id) },
                    onCancel: { model.cancel() }
                )
            }
        }
    }
}

private struct PortRowView: View {
    let port: ListeningPort
    let isArmed: Bool
    let onArm: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var scopeText: String {
        switch port.scope {
        case .allInterfaces: return "OPEN TO NETWORK"
        case .loopbackOnly: return "LOCAL ONLY"
        case .specific: return "BOUND ADDRESS"
        }
    }

    private var scopeColor: Color {
        switch port.scope {
        case .allInterfaces: return LCARSColor.paleCanary
        case .loopbackOnly: return LCARSColor.iceBlue
        case .specific: return LCARSColor.periwinkle
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(isArmed ? LCARSColor.alertRed : LCARSColor.orange))
                .frame(width: 130, height: 40)
                .overlay(alignment: .trailing) {
                    Text(String(port.port))
                        .font(LCARSFont.antonio(22, weight: 700))
                        .foregroundStyle(.black)
                        .padding(.trailing, 12)
                }

            Text(port.processCount > 1 ? "\(port.name.uppercased()) \u{00D7}\(port.processCount)" : port.name.uppercased())
                .font(LCARSFont.antonio(22, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(scopeText)
                .font(LCARSFont.antonio(14, weight: 700))
                .tracking(1.5)
                .foregroundStyle(scopeColor)
                .frame(width: 150, alignment: .trailing)

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
        } else if port.canTerminate {
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

/// A row of segments, lit from the left up to `fraction`.
struct LCARSSegmentBar: View {
    let fraction: Double?
    let color: Color
    var segments = 40

    private var lit: Int {
        guard let fraction else { return 0 }
        return max(0, min(segments, Int((fraction * Double(segments)).rounded())))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < lit ? color : Color.white.opacity(0.07))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }
}
