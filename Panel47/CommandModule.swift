import Foundation

/// One quick action a module can offer — a title for its button and the
/// literal command line to type into the active session for you.
struct CommandAction: Identifiable {
    let id = UUID()
    let title: String
    let command: String
}

/// A group of quick actions for a CLI tool the user actually has installed.
/// Buttons don't run anything invisibly — they just type the command into
/// the live shell, the same as if you'd typed it yourself.
struct CommandModule: Identifiable {
    let id = UUID()
    let name: String
    let actions: [CommandAction]
}

/// Detects which CLI tools are present on this machine and builds the
/// matching command module — so the UI only ever offers actions for things
/// that are actually installed. Detection is a plain executable-file check,
/// injectable so it's testable without depending on the real filesystem.
enum ToolDetector {
    static func detectHomebrew(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> CommandModule? {
        let candidatePaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard candidatePaths.contains(where: fileExists) else { return nil }

        return CommandModule(name: "Brew", actions: [
            CommandAction(title: "Update", command: "brew update"),
            CommandAction(title: "Outdated", command: "brew outdated"),
            CommandAction(title: "Upgrade", command: "brew upgrade"),
            CommandAction(title: "Doctor", command: "brew doctor"),
            CommandAction(title: "Cleanup", command: "brew cleanup"),
            CommandAction(title: "List", command: "brew list"),
        ])
    }

    static func detectAll(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> [CommandModule] {
        [detectHomebrew(fileExists: fileExists)].compactMap { $0 }
    }
}
