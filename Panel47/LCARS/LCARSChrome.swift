import SwiftUI

/// The full-screen panels that swap into the viewscreen from the sidebar.
enum SidebarPanel: Equatable {
    case calculator, status, engineering, comms, security, cargoBay, tactical

    var titleBarLabel: String {
        switch self {
        case .calculator: return "CALCULATOR"
        case .status: return "STATUS"
        case .engineering: return "ENGINEERING"
        case .comms: return "COMMS"
        case .security: return "SECURITY"
        case .cargoBay: return "CARGO BAY"
        case .tactical: return "TACTICAL"
        }
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
    @StateObject private var commandRunner = ShellCommandRunner()
    @StateObject private var brewOutdated = BrewOutdatedChecker()
    @StateObject private var statusModel = SystemStatusModel()
    @StateObject private var processModel = ProcessListModel()
    @StateObject private var commsModel = CommsModel()
    @StateObject private var securityModel = SecurityModel()
    @StateObject private var cargoModel = CargoModel()
    @StateObject private var tacticalModel: TacticalModel

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
            LCARSEngineeringView(model: processModel)
        } else if activePanel == .comms {
            LCARSCommsView(model: commsModel)
        } else if activePanel == .security {
            LCARSSecurityView(model: securityModel)
        } else if activePanel == .cargoBay {
            LCARSCargoBayView(model: cargoModel)
        } else if activePanel == .tactical {
            LCARSTacticalView(model: tacticalModel)
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
            if isGitRepository {
                panelButton("Tactical", .tactical)
            }

            sessionList

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
                    .padding(.trailing, 24)
            }
    }

    private var titleBarLabel: String {
        if let panel = activePanel {
            return panel.titleBarLabel
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
