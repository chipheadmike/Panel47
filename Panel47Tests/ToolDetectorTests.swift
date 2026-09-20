import Testing
@testable import Panel47

struct ToolDetectorTests {
    @Test func detectsHomebrewWhenAppleSiliconPathExists() {
        let module = ToolDetector.detectHomebrew { path in path == "/opt/homebrew/bin/brew" }
        #expect(module?.name == "Brew")
        #expect(module?.actions.isEmpty == false)
    }

    @Test func detectsHomebrewWhenIntelPathExists() {
        let module = ToolDetector.detectHomebrew { path in path == "/usr/local/bin/brew" }
        #expect(module?.name == "Brew")
    }

    @Test func returnsNilWhenNeitherPathExists() {
        let module = ToolDetector.detectHomebrew { _ in false }
        #expect(module == nil)
    }

    @Test func everyActionIsARealBrewCommand() {
        let module = ToolDetector.detectHomebrew { _ in true }!
        for action in module.actions {
            #expect(action.command.hasPrefix("brew "))
        }
    }

    @Test func detectAllOmitsUndetectedTools() {
        let modules = ToolDetector.detectAll { _ in false }
        #expect(modules.isEmpty)
    }
}
