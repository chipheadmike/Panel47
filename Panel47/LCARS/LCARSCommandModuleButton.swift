import SwiftUI

/// A sidebar button for a detected CLI tool (e.g. Homebrew) that reveals its
/// quick actions in a popover. Selecting one types the real command into the
/// active session — this isn't a hidden runner, it's a shortcut for typing.
struct LCARSCommandModuleButton: View {
    let module: CommandModule
    let color: Color
    let onSelect: (CommandAction) -> Void

    @State private var showingActions = false

    var body: some View {
        LCARSButton(title: module.name, color: color) {
            showingActions = true
        }
        .popover(isPresented: $showingActions) {
            VStack(alignment: .leading, spacing: 8) {
                Text(module.name.uppercased())
                    .font(LCARSFont.antonio(16, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                ForEach(module.actions) { action in
                    LCARSButton(title: action.title, color: color) {
                        onSelect(action)
                        showingActions = false
                    }
                }
            }
            .padding(16)
            .frame(width: 220)
            .background(LCARSColor.background)
        }
    }
}
