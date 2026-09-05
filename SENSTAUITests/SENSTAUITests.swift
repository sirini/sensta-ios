import XCTest

final class SENSTAUITests: XCTestCase {
  @MainActor
  func testPaginationFailureRetryPreservesFullScreenPages() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-pagination"]
    app.launch()
    XCTAssertTrue(app.staticTexts["테스트 사진 1"].waitForExistence(timeout: 10))
    for number in 2...4 {
      app.swipeUp(velocity: .slow)
      let title = app.staticTexts["테스트 사진 \(number)"]
      XCTAssertTrue(title.waitForExistence(timeout: 5))
      XCTAssertTrue(title.isHittable)
    }
    let retry = app.buttons["photo-feed-load-more-retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    retry.tap()
    XCTAssertTrue(app.staticTexts["테스트 사진 4"].isHittable)
    app.swipeUp(velocity: .slow)
    XCTAssertTrue(app.staticTexts["테스트 사진 5"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["테스트 사진 5"].isHittable)
    app.swipeUp(velocity: .slow)
    XCTAssertTrue(app.staticTexts["테스트 사진 6"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["테스트 사진 6"].isHittable)
    XCTAssertFalse(retry.exists)
  }

  @MainActor
  func testLaunchesWithBrand() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(
      app.images.matching(identifier: "sensta-feed-wordmark").firstMatch.waitForExistence(
        timeout: 30
      )
    )
  }

  @MainActor
  func testFeedFillsScreenWithSenstaWordmark() throws {
    let app = XCUIApplication()
    app.launch()

    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 30))
    let windowFrame = app.windows.firstMatch.frame
    XCTAssertEqual(card.frame.minX, windowFrame.minX, accuracy: 1)
    XCTAssertEqual(card.frame.maxX, windowFrame.maxX, accuracy: 1)
    XCTAssertEqual(card.frame.minY, windowFrame.minY, accuracy: 1)
    XCTAssertEqual(card.frame.maxY, windowFrame.maxY, accuracy: 1)
    XCTAssertTrue(
      app.images.matching(identifier: "sensta-feed-wordmark").firstMatch.exists
    )
  }

  @MainActor
  func testOpensPhotoDetailFromFeed() throws {
    let app = XCUIApplication()
    app.launch()

    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 30))
    card.tap()

    XCTAssertTrue(
      app.staticTexts.matching(identifier: "photo-detail-title").firstMatch.waitForExistence(
        timeout: 30
      )
    )

    let pager = app.otherElements.matching(identifier: "photo-detail-image-pager").firstMatch
    XCTAssertTrue(pager.waitForExistence(timeout: 5))
    let windowFrame = app.windows.firstMatch.frame
    XCTAssertEqual(pager.frame.minX, windowFrame.minX + 16, accuracy: 1)
    XCTAssertEqual(pager.frame.maxX, windowFrame.maxX - 16, accuracy: 1)
  }
}
