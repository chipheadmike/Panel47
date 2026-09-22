import SwiftUI

/// The full-screen panels that swap into the viewscreen from the sidebar.
enum SidebarPanel: Equatable {
    case calculator, status, engineering, comms, security, cargoBay, tactical, navigator

    var titleBarLabel: String {
        switch self {
        case .calculator: return "CALCULATOR"
        case .status: return "STATUS"
        case .engineering: return "ENGINEERING"
        case .comms: return "COMMS"
        case .security: return "SECURITY"
        case .cargoBay: return "CARGO BAY"
        case .tactical: return "TACTICAL"
        case .navigator: return "NAVIGATOR"
        }
    }
}

enum TitleBarFormat {
    /// Keeps "PANEL 47 · <PANEL NAME> ·" always intact in the title bar —
    /// only the path itself gets clipped (from the front, keeping the most
    /// specific, currently-relevant end) once it's long enough to need it.
    static func truncatedPathSuffix(_ path: String, keepingLast maxLength: Int = 40) -> String {
        guard path.count > maxLength else { return path }
        return "\u{2026}" + path.suffix(maxLength)
    }
}

/// The real window chrome: a swept corner over a button sidebar on the left,
/// thin title/status bars top and bottom, with the active session(s) — or a
/// command module's actions, or a command's running output — filling the
/// black frame in between.
struct LCARSChrome: View {
    @ObservedObject var store: TerminalSessionStore
    @ObservedObject var settings: AppSettings
    @Binding var showingSettings: Bool

    @State private var activeModule: CommandModule?
    @State private var runningAction: CommandAction?
    @State private var activePanel: SidebarPanel?
    @State private var calculator = CalculatorEngine()
    @StateObject private var commandRunner = PTYCommandRunner()
    @StateObject private var brewOutdated = BrewOutdatedChecker()
    @StateObject private var statusModel = SystemStatusModel()
    @StateObject private var processModel = ProcessListModel()
    @StateObject private var commsModel = CommsModel()
    @StateObject private var securityModel = SecurityModel()
    @StateObject private var cargoModel = CargoModel()
    @StateObject private var tacticalModel: TacticalModel
    @StateObject private var navigatorModel: FileBrowserModel

    private let sidebarWidth: CGFloat = 180
    private let barHeight: CGFloat = 36
    private let elbowHeight: CGFloat = 96
    private let gutter: CGFloat = 4
    private let commandModules = ToolDetector.detectAll()
    /// Checked once at launch, the same as `commandModules` — a directory
    /// changed in Settings after that won't retroactively show or hide the
    /// button until the app restarts.
    private let isGitRepository: Bool

    init(store: TerminalSessionStore, settings: AppSettings, showingSettings: Binding<Bool>) {
        self.store = store
        self.settings = settings
        self._showingSettings = showingSettings
        let directory = settings.workingDirectory.isEmpty ? NSHomeDirectory() : settings.workingDirectory
        self._tacticalModel = StateObject(wrappedValue: TacticalModel(directory: directory))
        self._navigatorModel = StateObject(wrappedValue: FileBrowserModel(rootPath: directory))
        self.isGitRepository = GitSampler.isRepository(directory: directory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clears the traffic lights from the hidden title bar.
            Color.clear.frame(height: 28)

            HStack(alignment: .top, spacing: gutter) {
                sidebar
                    .frame(width: sidebarWidth)

                VStack(spacing: gutter) {
                    titleBar

                    contentArea
                        .frame(maxHeight: .infinity)

                    statusBar
                }
            }
        }
        .padding(gutter)
        .background(
            ZStack {
                LCARSVibrancyBackground()
                LCARSColor.background.opacity(0.92)
            }
        )
    }

    @ViewBuilder
    private var contentArea: some View {
        if activePanel == .calculator {
            LCARSCalculatorView(engine: $calculator, onKeyPress: playBlip)
        } else if activePanel == .status {
            LCARSStatusView(model: statusModel)
        } else if activePanel == .engineering {
            LCARSEngineeringView(model: processModel, playBlip: playBlip)
        } else if activePanel == .comms {
            LCARSCommsView(model: commsModel, playBlip: playBlip)
        } else if activePanel == .security {
            LCARSSecurityView(model: securityModel)
        } else if activePanel == .cargoBay {
            LCARSCargoBayView(model: cargoModel, playBlip: playBlip)
        } else if activePanel == .tactical {
            LCARSTacticalView(model: tacticalModel, playBlip: playBlip)
        } else if activePanel == .navigator {
            LCARSNavigatorView(model: navigatorModel, playBlip: playBlip)
        } else if let module = activeModule, let action = runningAction {
            LCARSCommandRunView(module: module, action: action, runner: commandRunner) {
                runningAction = nil
            } onRunAgain: {
                commandRunner.run(action.command)
            }
        } else if let module = activeModule {
            LCARSCommandModulePanel(
                module: module,
                outdated: module.tracksOutdatedPackages ? brewOutdated : nil,
                onSelect: { action in
                    playBlip()
                    runningAction = action
                    commandRunner.run(action.command)
                },
                onUpgrade: { package in
                    playBlip()
                    let action = package.upgradeAction
                    runningAction = action
                    commandRunner.run(action.command)
                }
            )
        } else if store.isSplit {
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
                .fill(LCARSColor.gloss(LCARSColor.orange))
                .frame(height: elbowHeight)

            sidebarBody

            Spacer(minLength: 8)

            Text(Date(), style: .time)
                .font(LCARSFont.antonio(22, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)

            LCARSStardateView()

            LCARSElbow(corner: .bottomLeft, armThickness: barHeight, outerRadius: 64)
                .fill(LCARSColor.gloss(LCARSColor.peach))
                .frame(height: elbowHeight)
        }
    }

    /// The sidebar's main content: the full main menu normally, or — once a
    /// panel has taken over the screen — that panel's own controls in its
    /// place. Not every panel has been migrated to this yet; the rest still
    /// fall back to the main menu for now.
    @ViewBuilder
    private var sidebarBody: some View {
        if activePanel == .status {
            EmptyView()
        } else if activePanel == .engineering {
            EngineeringSidebarControls(model: processModel, playBlip: playBlip)
        } else if activePanel == .comms {
            CommsSidebarControls(model: commsModel, playBlip: playBlip)
        } else if activePanel == .security {
            EmptyView()
        } else if activePanel == .cargoBay {
            CargoBaySidebarControls(model: cargoModel, playBlip: playBlip)
        } else if activePanel == .tactical {
            TacticalSidebarControls(model: tacticalModel, playBlip: playBlip)
        } else if activePanel == .navigator {
            NavigatorSidebarControls(model: navigatorModel, playBlip: playBlip)
        } else {
            mainMenu
        }
    }

    @ViewBuilder
    private var mainMenu: some View {
        LCARSButton(title: "New Session", color: LCARSColor.orange) {
            playBlip()
            showTerminal()
            store.newSession()
        }
        LCARSButton(title: store.isSplit ? "Unsplit" : "Split Pane", color: LCARSColor.periwinkle) {
            playBlip()
            showTerminal()
            store.toggleSplit()
        }
        LCARSButton(title: "Settings", color: LCARSColor.lilac) {
            playBlip()
            showingSettings = true
        }

        ForEach(commandModules) { module in
            LCARSButton(
                title: module.name,
                color: activeModule?.id == module.id ? LCARSColor.paleCanary : LCARSColor.peach
            ) {
                playBlip()
                runningAction = nil
                activePanel = nil
                activeModule = (activeModule?.id == module.id) ? nil : module
            }
        }

        panelButton("Calc", .calculator)
        panelButton("Status", .status)
        panelButton("Engineering", .engineering)
        panelButton("Comms", .comms)
        panelButton("Security", .security)
        panelButton("Cargo Bay", .cargoBay)
        panelButton("Navigator", .navigator)
        if isGitRepository {
            panelButton("Tactical", .tactical)
        }

        sessionList
    }

    private func panelButton(_ title: String, _ panel: SidebarPanel) -> some View {
        LCARSButton(title: title, color: activePanel == panel ? LCARSColor.paleCanary : LCARSColor.peach) {
            playBlip()
            activeModule = nil
            runningAction = nil
            activePanel = (activePanel == panel) ? nil : panel
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
                        playBlip()
                        showTerminal()
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
            .fill(LCARSColor.gloss(LCARSColor.orange))
            .frame(height: barHeight)
            .overlay(alignment: .trailing) {
                Text("PANEL 47 \u{00B7} \(titleBarLabel)")
                    .font(LCARSFont.antonio(18, weight: 700))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 24)
                    .padding(.leading, 24)
            }
    }

    private var titleBarLabel: String {
        if let panel = activePanel {
            // These two drill into a directory, and the content area scrolls
            // — showing the path here too keeps it visible even once the
            // current folder's row has scrolled out of view.
            switch panel {
            case .navigator: return "NAVIGATOR \u{00B7} \(TitleBarFormat.truncatedPathSuffix(navigatorModel.displayPath).uppercased())"
            case .cargoBay: return "CARGO BAY \u{00B7} \(TitleBarFormat.truncatedPathSuffix(cargoModel.displayPath).uppercased())"
            default: return panel.titleBarLabel
            }
        } else if let module = activeModule, let action = runningAction {
            return "\(module.name.uppercased()) \u{00B7} \(action.title.uppercased())"
        } else if let module = activeModule {
            return module.name.uppercased()
        } else {
            return "TERMINAL"
        }
    }

    private var statusBar: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: barHeight / 2, topTrailingRadius: 0)
            .fill(LCARSColor.gloss(LCARSColor.peach))
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                LCARSReadout()
                    .padding(.leading, 20)
            }
            .overlay(alignment: .trailing) {
                // Always present, regardless of what's taken over the
                // screen — the one guaranteed way back to the main menu.
                Button {
                    playBlip()
                    showTerminal()
                } label: {
                    Text("MAIN")
                        .font(LCARSFont.antonio(16, weight: 700))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(LCARSColor.gloss(LCARSColor.orange)))
                .padding(.trailing, 12)
            }
    }

    private func showTerminal() {
        activeModule = nil
        runningAction = nil
        activePanel = nil
    }

    private func playBlip() {
        if settings.soundEffectsEnabled {
            LCARSSoundPlayer.shared.playBlip()
        }
    }
}
