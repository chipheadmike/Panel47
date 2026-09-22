import SwiftUI

/// Shows a running (or finished) command's output in LCARS style — Antonio
/// throughout, no terminal chrome, no cursor, no ANSI. This is the "get away
/// from seeing the terminal at all" surface.
struct LCARSCommandRunView: View {
    let module: CommandModule
    let action: CommandAction
    @ObservedObject var runner: PTYCommandRunner
    let onBack: () -> Void
    let onRunAgain: () -> Void

    @State private var passwordEntry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Text(action.title.uppercased())
                    .font(LCARSFont.antonio(36, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                statusBadge

                Spacer()

                LCARSButton(title: "Back", color: LCARSColor.periwinkle, alignment: .center, action: onBack)
                    .frame(width: 130)
            }

            Text(action.command)
                .font(LCARSFont.antonio(14, weight: 400))
                .tracking(0.5)
                .foregroundStyle(.gray)

            outputLog

            if let prompt = runner.passwordPrompt {
                passwordPromptRow(prompt)
            } else if !runner.isRunning {
                LCARSButton(title: "Run Again", color: LCARSColor.orange, alignment: .center, action: onRunAgain)
                    .frame(width: 180)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LCARSColor.background)
    }

    /// Shown in place of the output log's usual footer while a command is
    /// waiting on a detected `sudo`-style password prompt. The password is
    /// only ever held in this view's own transient `@State`, sent straight
    /// to the process, and cleared immediately after — never appended to
    /// `outputLines` or stored anywhere else.
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
        runner.submitPassword(passwordEntry)
        passwordEntry = ""
    }

    private var outputLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(runner.outputLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(LCARSFont.antonio(16, weight: 400))
                            .foregroundStyle(LCARSColor.textOnBlack)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: runner.outputLines.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.04))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if runner.isRunning {
            badge("RUNNING", color: LCARSColor.paleCanary)
        } else if let code = runner.exitCode {
            badge(code == 0 ? "COMPLETE" : "FAILED \u{00B7} \(code)", color: code == 0 ? LCARSColor.iceBlue : LCARSColor.alertRed)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(LCARSFont.antonio(16, weight: 700))
            .tracking(0.5)
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Capsule().fill(LCARSColor.gloss(color)))
    }
}
