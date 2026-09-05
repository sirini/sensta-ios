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
  func testPhotoViewerZoomPagingAndDismissal() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    let open = app.buttons.matching(identifier: "photo-detail-open-viewer").firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    open.tap()
    let photo = app.images.matching(identifier: "photo-zoom-view").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 10))
    XCTAssertEqual(photo.value as? String, "100%")
    photo.doubleTap()
    XCTAssertNotEqual(photo.value as? String, "100%")
    photo.doubleTap()
    XCTAssertEqual(photo.value as? String, "100%")
    app.buttons["다음 사진"].tap()
    XCTAssertTrue(app.navigationBars["2 / 2"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Photo viewer"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["photo-viewer-close"].tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testInlineCommentsRetryPaginationAndScrolling() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 10))
    let retry = app.buttons["photo-comments-retry"]
    for _ in 0..<5 {
      if retry.exists && retry.isHittable { break }
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(retry.isHittable)
    XCTAssertEqual(app.sheets.count, 0)
    retry.tap()
    XCTAssertTrue(app.staticTexts["여백이 아름다운 사진입니다. 1"].waitForExistence(timeout: 5))
    let more = app.buttons["댓글 더 보기"]
    for _ in 0..<4 {
      if more.exists && more.isHittable { break }
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(more.isHittable)
    more.tap()
    XCTAssertTrue(app.staticTexts["여백이 아름다운 사진입니다. 2"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Photo comments"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertTrue(app.navigationBars["사진"].exists)
    XCTAssertEqual(app.sheets.count, 0)
  }

  @MainActor
  func testMetadataPanelInLightDarkAndLargeText() throws {
    for appearance in ["light", "dark", "large-text"] {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-viewer", "--ui-test-\(appearance)"]
      app.launch()
      let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
      XCTAssertTrue(card.waitForExistence(timeout: 10))
      card.tap()
      XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 10))
      let panel = app.otherElements["photo-metadata-panel"]
      let exif = app.staticTexts["photo-metadata-exif"]
      let description = app.staticTexts["photo-metadata-description"]
      for _ in 0..<4 {
        if description.exists && description.isHittable { break }
        app.swipeUp(velocity: .slow)
      }
      XCTAssertTrue(panel.exists)
      XCTAssertTrue(exif.exists)
      XCTAssertTrue(description.isHittable)
      XCTAssertLessThan(exif.frame.maxY, description.frame.minY)
      XCTAssertGreaterThanOrEqual(panel.frame.minX, app.windows.firstMatch.frame.minX + 15)
      XCTAssertLessThanOrEqual(panel.frame.maxX, app.windows.firstMatch.frame.maxX - 15)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Metadata \(appearance)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.buttons["photo-detail-comments"].tap()
      XCTAssertTrue(app.buttons["photo-comments-retry"].isHittable)
      XCTAssertEqual(app.sheets.count, 0)
      app.terminate()
    }
  }

  @MainActor
  func testSearchAndOpenResult() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let search = app.buttons["photo-feed-search"]
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("photo\n")
    XCTAssertTrue(app.staticTexts["AI 설명 검색 결과"].waitForExistence(timeout: 5))
    let result = app.buttons.matching(identifier: "photo-search-result").firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Photo search"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    result.tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testExploreLatestGridAndRecentTagSearch() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    XCTAssertTrue(app.buttons["photo-feed-search"].waitForExistence(timeout: 10))
    app.buttons["photo-feed-search"].tap()
    XCTAssertTrue(app.staticTexts["최근 사진"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons.matching(identifier: "photo-search-result").firstMatch.waitForExistence(
        timeout: 5))
    let tag = app.buttons["explore-tag-10"]
    XCTAssertTrue(tag.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Explore latest photos"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    tag.tap()
    XCTAssertTrue(app.staticTexts["해시태그 검색 결과"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "풍경")
    app.buttons["explore-option-0"].tap()
    XCTAssertTrue(app.staticTexts["제목 검색 결과"].waitForExistence(timeout: 5))
    app.buttons.matching(identifier: "photo-search-result").firstMatch.tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 5))
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
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Photo detail"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
