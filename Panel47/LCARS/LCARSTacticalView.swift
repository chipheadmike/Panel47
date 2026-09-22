import SwiftUI

/// Git status board for the configured working directory: branch and
/// ahead/behind, the working tree as a file list, and Fetch/Pull/Stash
/// actions that run in the background and stream their output here, the
/// same way BREW's actions do.
struct LCARSTacticalView: View {
    @ObservedObject var model: TacticalModel
    let playBlip: () -> Void

    @State private var passwordEntry = ""

    var body: some View {
        let status = model.status
        let alerts = status.map(GitAlertRules.reasons) ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("TACTICAL")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(alerts.isEmpty ? LCARSColor.textOnBlack : LCARSColor.alertRed)

                if !alerts.isEmpty {
                    alertBanner(alerts)
                }

                if let status {
                    branchReadouts(status.branchStatus)
                }

                if let notice = model.notice {
                    Text(notice)
                        .font(LCARSFont.antonio(18, weight: 400))
                        .tracking(0.5)
                        .foregroundStyle(LCARSColor.paleCanary)
                }

                if model.isActionRunning || !model.actionOutput.isEmpty {
                    actionOutputBlock
                }

                if let prompt = model.passwordPrompt {
                    passwordPromptRow(prompt)
                }

                if let status {
                    fileList(status)
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

    private func branchReadouts(_ branch: GitBranchStatus) -> some View {
        HStack(alignment: .top, spacing: 36) {
            readout("BRANCH", branch.isDetached ? "DETACHED HEAD" : (branch.branch ?? "\u{2014}"))
            readout("UPSTREAM", GitStatusFormat.aheadBehind(branch))
        }
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

    private var actionOutputBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((model.actionTitle ?? "ACTION") + (model.isActionRunning ? " \u{00B7} RUNNING" : " \u{00B7} DONE"))
                .font(LCARSFont.antonio(12, weight: 700))
                .tracking(1.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.actionOutput.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(LCARSColor.textOnBlack)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// The password is only ever held in this view's own transient
    /// `@State`, sent straight to the model, and cleared immediately after
    /// — never appended to `actionOutput` or stored anywhere else.
    private func passwordPromptRow(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.uppercased())
                .font(LCARSFont.antonio(18, weight: 700))
                .tracking(0.5)
                .foregroundStyle(LCARSColor.paleCanary)

            HStack(spacing: 10) {
                SecureField("", text: $passwordEntry)
                    .textFieldStyle(.plain)
                    .font(LCARSFont.antonio(18, weight: 400))
                    .foregroundStyle(LCARSColor.textOnBlack)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit(submitPassword)

                LCARSButton(title: "Submit", color: LCARSColor.paleCanary, alignment: .center, action: submitPassword)
                    .frame(width: 130)
            }
        }
    }

    private func submitPassword() {
        playBlip()
        model.submitPassword(passwordEntry)
        passwordEntry = ""
    }

    private func fileList(_ status: GitRepoStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKING TREE \u{00B7} \(status.files.count)")
                .font(LCARSFont.antonio(12, weight: 700))
                .tracking(1.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
                .padding(.top, 6)

            if status.files.isEmpty {
                Text("NOTHING TO COMMIT")
                    .font(LCARSFont.antonio(18, weight: 400))
                    .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
            }

            ForEach(status.files) { file in
                FileRowView(file: file)
            }
        }
    }

}

/// Fetch/Pull/Stash/Refresh controls shown in the sidebar in place of the
/// main menu while Tactical has taken over the screen.
struct TacticalSidebarControls: View {
    @ObservedObject var model: TacticalModel
    let playBlip: () -> Void

    private var busy: Bool { model.isActionRunning || model.isRefreshing }

    var body: some View {
        Group {
            sidebarButton("Fetch", LCARSColor.periwinkle) { model.fetch() }
            sidebarButton("Pull", LCARSColor.iceBlue) { model.pull() }
            sidebarButton("Stash", LCARSColor.peach) { model.stash() }
            sidebarButton("Refresh", LCARSColor.paleCanary) { model.refresh() }
        }
    }

    private func sidebarButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        LCARSButton(title: title, color: color) {
            playBlip()
            action()
        }
        .opacity(busy ? 0.4 : 1)
        .disabled(busy)
    }
}

private struct FileRowView: View {
    let file: GitFileStatus

    private var color: Color {
        switch file.kind {
        case .unmerged: return LCARSColor.alertRed
        case .untracked: return LCARSColor.peach
        case .renamed: return LCARSColor.periwinkle
        case .ordinary: return file.isStaged ? LCARSColor.iceBlue : LCARSColor.paleCanary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(LCARSColor.orange))
                .frame(width: 130, height: 36)
                .overlay(alignment: .trailing) {
                    Text(GitStatusFormat.label(file))
                        .font(LCARSFont.antonio(14, weight: 700))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.trailing, 10)
                }

            Circle().fill(color).frame(width: 10, height: 10)

            Text(file.path)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(LCARSColor.textOnBlack)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
