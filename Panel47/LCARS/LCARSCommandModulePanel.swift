import SwiftUI

/// Fills the terminal's content area with a module's actions — this is how
/// LCARS actually works: the main viewscreen swaps content, it doesn't pop
/// up a floating dialog on top of everything.
struct LCARSCommandModulePanel: View {
    let module: CommandModule
    /// Present only for modules that track pending updates (Homebrew).
    var outdated: BrewOutdatedChecker?
    let onSelect: (CommandAction) -> Void
    var onUpgrade: (OutdatedPackage) -> Void = { _ in }

    private let palette: [Color] = [
        LCARSColor.orange, LCARSColor.periwinkle, LCARSColor.lilac,
        LCARSColor.paleCanary, LCARSColor.iceBlue, LCARSColor.peach,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(module.name.uppercased())
                .font(LCARSFont.antonio(44, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(module.actions.enumerated()), id: \.element.id) { index, action in
                    LCARSButton(
                        title: action.title,
                        color: palette[index % palette.count],
                        alignment: .center
                    ) {
                        onSelect(action)
                    }
                }
            }

            if let outdated {
                LCARSOutdatedSection(checker: outdated, onUpgrade: onUpgrade)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Spacer()
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LCARSColor.background)
    }
}
