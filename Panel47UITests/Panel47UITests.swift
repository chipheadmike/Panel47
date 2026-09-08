import XCTest

final class Panel47UITests: XCTestCase {
    func testLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
