import XCTest

final class SENSTAUITests: XCTestCase {
  @MainActor
  func testLaunchesWithBrand() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["SENSTA"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testFeedUsesFixedHorizontalMargins() throws {
    let app = XCUIApplication()
    app.launch()

    let card = app.otherElements.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 30))
    let windowFrame = app.windows.firstMatch.frame
    XCTAssertEqual(card.frame.minX, windowFrame.minX + 12, accuracy: 1)
    XCTAssertEqual(card.frame.maxX, windowFrame.maxX - 12, accuracy: 1)
  }
}
