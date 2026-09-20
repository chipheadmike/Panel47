import SwiftUI

/// Lists packages with pending updates, one upgrade button each. Re-checks
/// whenever it appears, so coming back from an upgrade shows fresh results.
struct LCARSOutdatedSection: View {
    @ObservedObject var checker: BrewOutdatedChecker
    let onUpgrade: (OutdatedPackage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("OUTDATED")
                    .font(LCARSFont.antonio(26, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                statusBadge

                Spacer()

                LCARSButton(title: "Recheck", color: LCARSColor.periwinkle, alignment: .center) {
                    checker.refresh()
                }
                .frame(width: 130)
            }

            content
        }
        .onAppear { checker.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch checker.state {
        case .idle, .checking:
            note("Checking for updates\u{2026}", color: .gray)
        case .failed:
            note("Couldn\u{2019}t check for updates.", color: LCARSColor.alertRed)
        case .ready(let packages) where packages.isEmpty:
            note("All packages are current.", color: LCARSColor.textOnBlack)
        case .ready(let packages):
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(packages) { package in
                        upgradeButton(package)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if case .ready(let packages) = checker.state, !packages.isEmpty {
            Text("\(packages.count) PENDING")
                .font(LCARSFont.antonio(16, weight: 700))
                .tracking(0.5)
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Capsule().fill(LCARSColor.gloss(LCARSColor.paleCanary)))
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(LCARSFont.antonio(18, weight: 400))
            .tracking(0.5)
            .foregroundStyle(color)
    }

    private func upgradeButton(_ package: OutdatedPackage) -> some View {
        Button {
            onUpgrade(package)
        } label: {
            HStack(spacing: 8) {
                Text(package.name.uppercased())
                    .font(LCARSFont.antonio(18, weight: 700))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                if !package.latestVersion.isEmpty {
                    Text("\(package.installedVersion) \u{2192} \(package.latestVersion)")
                        .font(LCARSFont.antonio(14, weight: 400))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(LCARSColor.gloss(LCARSColor.iceBlue)))
        }
        .buttonStyle(.plain)
    }
}
