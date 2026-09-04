import XCTest

final class SENSTAUITests: XCTestCase {
  @MainActor
  func testLaunchesWithBrand() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["SENSTA"].waitForExistence(timeout: 5))
  }
}
