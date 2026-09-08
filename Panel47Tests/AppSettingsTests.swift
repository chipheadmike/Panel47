import Foundation
import Testing
@testable import Panel47

struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "Panel47Tests.\(UUID().uuidString)")!
    }

    @Test func defaultsWhenNothingStored() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.fontSize == 13)
        #expect(settings.colorScheme == .classic)
        #expect(settings.customShellPath == "")
        #expect(settings.workingDirectory == "")
    }

    @Test func persistsAcrossInstancesSharingTheSameDefaults() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.fontSize = 18
        first.colorScheme = .amber
        first.customShellPath = "/bin/bash"
        first.workingDirectory = "/tmp"

        let second = AppSettings(defaults: defaults)
        #expect(second.fontSize == 18)
        #expect(second.colorScheme == .amber)
        #expect(second.customShellPath == "/bin/bash")
        #expect(second.workingDirectory == "/tmp")
    }

    @Test func separateDefaultsSuitesDoNotLeakIntoEachOther() {
        let a = AppSettings(defaults: freshDefaults())
        a.fontSize = 22

        let b = AppSettings(defaults: freshDefaults())
        #expect(b.fontSize == 13)
    }
}
