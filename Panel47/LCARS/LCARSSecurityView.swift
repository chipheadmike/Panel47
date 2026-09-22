import SwiftUI

/// Security posture board: FileVault, the firewall, Gatekeeper, System
/// Integrity Protection, and the Time Machine backup age. Refreshes slowly,
/// and only while shown — none of this changes second to second.
struct LCARSSecurityView: View {
    @ObservedObject var model: SecurityModel

    var body: some View {
        let alerts = SecurityMath.alertReasons(model.checks)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SECURITY")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(alerts.isEmpty ? LCARSColor.textOnBlack : LCARSColor.alertRed)

                if !alerts.isEmpty {
                    alertBanner(alerts)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.checks) { check in
                        CheckRowView(check: check)
                    }
                }

                if let updated = model.lastUpdated {
                    Text("LAST CHECKED \(updated, style: .time)")
                        .font(LCARSFont.antonio(12, weight: 700))
                        .tracking(1.5)
                        .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
                        .padding(.top, 4)
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
    }
}

private struct CheckRowView: View {
    let check: SecurityCheck

    private var color: Color {
        switch check.state {
        case .good: return LCARSColor.iceBlue
        case .bad: return LCARSColor.alertRed
        case .unknown: return LCARSColor.peach
        }
    }

    private var lampFraction: Double {
        switch check.state {
        case .good: return 1
        case .bad: return 1
        case .unknown: return 0.3
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(LCARSColor.orange))
                .frame(width: 200, height: 40)
                .overlay(alignment: .trailing) {
                    Text(check.label)
                        .font(LCARSFont.antonio(18, weight: 700))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.trailing, 12)
                }

            LCARSSegmentBar(fraction: lampFraction, color: color, segments: 12)
                .frame(maxWidth: 220)

            Text(check.detail)
                .font(LCARSFont.antonio(20, weight: 700))
                .foregroundStyle(check.state == .bad ? LCARSColor.alertRed : LCARSColor.textOnBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
