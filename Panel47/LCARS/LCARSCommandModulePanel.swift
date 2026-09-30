import SwiftUI

/// Fills the terminal's content area with a module's own data — this is how
/// LCARS actually works: the main viewscreen swaps content, it doesn't pop
/// up a floating dialog on top of everything. The module's actions live in
/// the sidebar (see `CommandModuleSidebarControls`), not here.
struct LCARSCommandModulePanel: View {
    let module: CommandModule
    /// Present only for modules that track pending updates (Homebrew).
    var outdated: BrewOutdatedChecker?
    var onUpgrade: (OutdatedPackage) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(module.name.uppercased())
                .font(LCARSFont.antonio(44, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

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

/// A module's action buttons, shown in the sidebar in place of the main menu
/// while that module has taken over the screen — mirrors the per-panel
/// sidebar-controls structs (`EngineeringSidebarControls` etc.). Picking a
/// different action while one is already running switches to it directly
/// (the runner stops the old one first); there's no need to return to a
/// grid to change your mind.
struct CommandModuleSidebarControls: View {
    let module: CommandModule
    let playBlip: () -> Void
    let onSelect: (CommandAction) -> Void

    private let palette: [Color] = [
        LCARSColor.orange, LCARSColor.periwinkle, LCARSColor.lilac,
        LCARSColor.paleCanary, LCARSColor.iceBlue, LCARSColor.peach,
    ]

    var body: some View {
        ForEach(Array(module.actions.enumerated()), id: \.element.id) { index, action in
            LCARSButton(title: action.title, color: palette[index % palette.count]) {
                playBlip()
                onSelect(action)
            }
        }
    }
}
