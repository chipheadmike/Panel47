import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("SETTINGS")
                .font(LCARSFont.antonio(30, weight: 700))
                .foregroundStyle(LCARSColor.orange)

            section("FONT SIZE") {
                HStack {
                    Slider(value: $settings.fontSize, in: 9...24, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .font(LCARSFont.antonio(16, weight: 600))
                        .foregroundStyle(.white)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            section("TERMINAL COLOR SCHEME") {
                HStack(spacing: 8) {
                    ForEach(TerminalColorScheme.allCases) { scheme in
                        LCARSButton(
                            title: scheme.rawValue,
                            color: settings.colorScheme == scheme ? LCARSColor.paleCanary : LCARSColor.iceBlue,
                            alignment: .center
                        ) {
                            settings.colorScheme = scheme
                        }
                    }
                }
            }

            section("SHELL \u{00B7} blank uses the system default") {
                TextField("/bin/zsh", text: $settings.customShellPath)
                    .textFieldStyle(.roundedBorder)
            }

            section("WORKING DIRECTORY \u{00B7} new sessions only, blank uses home") {
                HStack {
                    TextField("~", text: $settings.workingDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose\u{2026}") { chooseDirectory() }
                }
            }

            section("UI SOUNDS") {
                HStack(spacing: 8) {
                    LCARSButton(
                        title: "On",
                        color: settings.soundEffectsEnabled ? LCARSColor.paleCanary : LCARSColor.iceBlue,
                        alignment: .center
                    ) {
                        settings.soundEffectsEnabled = true
                    }
                    LCARSButton(
                        title: "Off",
                        color: !settings.soundEffectsEnabled ? LCARSColor.paleCanary : LCARSColor.iceBlue,
                        alignment: .center
                    ) {
                        settings.soundEffectsEnabled = false
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                LCARSButton(title: "Done", color: LCARSColor.orange, alignment: .center) {
                    dismiss()
                }
                .frame(width: 140)
            }
        }
        .padding(28)
        .frame(width: 480, height: 560)
        .background(LCARSColor.background)
    }

    @ViewBuilder
    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(LCARSFont.antonio(13, weight: 700))
                .tracking(0.5)
                .foregroundStyle(LCARSColor.textOnBlack)
            content()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.workingDirectory = url.path
        }
    }
}
