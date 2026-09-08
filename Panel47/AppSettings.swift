import AppKit
import Foundation

/// A terminal foreground/background pairing. Distinct from the LCARS chrome
/// palette, which stays fixed — this only affects the text inside the panes.
enum TerminalColorScheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case amber = "LCARS Amber"
    case ice = "Ice Blue"

    var id: String { rawValue }

    var background: NSColor {
        switch self {
        case .classic: return .black
        case .amber: return .black
        case .ice: return NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.08, alpha: 1)
        }
    }

    var foreground: NSColor {
        switch self {
        case .classic: return NSColor(calibratedWhite: 0.9, alpha: 1)
        case .amber: return NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .ice: return NSColor(calibratedRed: 0.6, green: 0.8, blue: 1.0, alpha: 1)
        }
    }
}

/// User-configurable settings, persisted to `UserDefaults`. Font size and color
/// scheme apply live to every open session; shell path and working directory
/// only take effect for sessions created afterward (a running shell can't be
/// retroactively re-launched into a different directory).
final class AppSettings: ObservableObject {
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var colorScheme: TerminalColorScheme { didSet { defaults.set(colorScheme.rawValue, forKey: Keys.colorScheme) } }
    @Published var customShellPath: String { didSet { defaults.set(customShellPath, forKey: Keys.customShellPath) } }
    @Published var workingDirectory: String { didSet { defaults.set(workingDirectory, forKey: Keys.workingDirectory) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let fontSize = "Panel47.fontSize"
        static let colorScheme = "Panel47.colorScheme"
        static let customShellPath = "Panel47.customShellPath"
        static let workingDirectory = "Panel47.workingDirectory"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 13
        colorScheme = TerminalColorScheme(rawValue: defaults.string(forKey: Keys.colorScheme) ?? "") ?? .classic
        customShellPath = defaults.string(forKey: Keys.customShellPath) ?? ""
        workingDirectory = defaults.string(forKey: Keys.workingDirectory) ?? ""
    }
}
