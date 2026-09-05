import XCTest

final class SENSTAUITests: XCTestCase {
  @MainActor
  func testCommentLoginWriteReplyAndFailurePreservesDraft() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    let login = app.buttons["comment-login"]
    for _ in 0..<6 where !login.isHittable { app.swipeUp() }
    XCTAssertTrue(login.isHittable)
    login.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-logout"].waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()
    let commentLike = app.buttons["comment-like-1"]
    for _ in 0..<4 where !commentLike.isHittable { app.swipeUp() }
    XCTAssertEqual(commentLike.value as? String, "2개")
    commentLike.tap()
    expectation(
      for: NSPredicate(format: "label == %@ AND value == %@", "댓글 좋아요 취소", "3개"),
      evaluatedWith: commentLike)
    waitForExpectations(timeout: 5)
    let draft = app.descendants(matching: .any).matching(identifier: "comment-draft").firstMatch
    XCTAssertTrue(draft.waitForExistence(timeout: 5))
    for _ in 0..<3 where !draft.isHittable { app.swipeUp() }
    draft.tap()
    draft.typeText("Beautiful")
    let send = app.buttons["comment-send"]
    XCTAssertFalse(send.isEnabled)
    XCTAssertTrue(app.staticTexts["comment-minimum-length"].exists)
    draft.typeText(" photograph")
    XCTAssertTrue(send.isEnabled)
    XCTAssertFalse(app.staticTexts["comment-minimum-length"].exists)
    send.tap()
    for _ in 0..<4 where !app.staticTexts["Beautiful photograph"].exists { app.swipeUp() }
    XCTAssertTrue(app.staticTexts["Beautiful photograph"].waitForExistence(timeout: 5))
    XCTAssertFalse(send.isEnabled)
    let reply = app.buttons["comment-reply-101"]
    for _ in 0..<4 where !reply.isHittable { app.swipeUp() }
    reply.tap()
    XCTAssertTrue(app.staticTexts["테스트 사진가님에게 답글"].waitForExistence(timeout: 5))
    draft.tap()
    draft.typeText("Thank you for sharing")
    send.tap()
    XCTAssertTrue(app.staticTexts["Thank you for sharing"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Inline comment and reply"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    for _ in 0..<4 where !draft.isHittable { app.swipeDown() }
    draft.tap()
    draft.typeText("reject this comment")
    send.tap()
    XCTAssertTrue(app.staticTexts["comment-write-error"].waitForExistence(timeout: 5))
    XCTAssertEqual(draft.value as? String, "reject this comment")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["photo-feed-comments-1"].label, "댓글 3개")
  }

  @MainActor
  func testOwnCommentEditAndDeletePreservesReplies() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    let login = app.buttons["comment-login"]
    for _ in 0..<6 where !login.isHittable { app.swipeUp() }
    login.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-logout"].waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()

    let draft = app.descendants(matching: .any).matching(identifier: "comment-draft").firstMatch
    XCTAssertTrue(draft.waitForExistence(timeout: 5))
    for _ in 0..<3 where !draft.isHittable { app.swipeUp() }
    draft.tap()
    draft.typeText("Original comment text")
    app.buttons["comment-send"].tap()
    let originalComment = app.staticTexts["Original comment text"]
    for _ in 0..<4 where !originalComment.exists { app.swipeUp() }
    XCTAssertTrue(originalComment.waitForExistence(timeout: 5))

    let edit = app.buttons["comment-edit-101"]
    for _ in 0..<4 where !edit.isHittable { app.swipeUp() }
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    let rootDelete = app.buttons["comment-delete-101"]
    XCTAssertTrue(rootDelete.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(edit.frame.width, 44)
    XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
    XCTAssertGreaterThanOrEqual(rootDelete.frame.width, 44)
    XCTAssertGreaterThanOrEqual(rootDelete.frame.height, 44)
    XCTAssertFalse(app.buttons["comment-manage-101"].exists)
    edit.tap()
    let editDraft = app.descendants(matching: .any).matching(identifier: "comment-edit-draft")
      .firstMatch
    XCTAssertTrue(editDraft.waitForExistence(timeout: 5))
    editDraft.tap()
    editDraft.typeKey("a", modifierFlags: .command)
    editDraft.typeText("Edited comment text")
    app.buttons["comment-edit-save"].tap()
    XCTAssertTrue(app.staticTexts["Edited comment text"].waitForExistence(timeout: 5))

    let reply = app.buttons["comment-reply-101"]
    for _ in 0..<4 where !reply.isHittable { app.swipeUp() }
    reply.tap()
    draft.tap()
    draft.typeText("Reply that must remain")
    app.buttons["comment-send"].tap()
    XCTAssertTrue(app.staticTexts["Reply that must remain"].waitForExistence(timeout: 5))

    for _ in 0..<4 where !rootDelete.isHittable { app.swipeUp() }
    rootDelete.tap()
    XCTAssertTrue(app.buttons["삭제하기"].waitForExistence(timeout: 5))
    app.buttons["삭제하기"].tap()
    XCTAssertTrue(app.staticTexts["삭제된 댓글입니다."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Reply that must remain"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Edited and deleted comment"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    let replyDelete = app.buttons["comment-delete-102"]
    for _ in 0..<4 where !replyDelete.isHittable { app.swipeUp() }
    replyDelete.tap()
    app.buttons["삭제하기"].tap()
    expectation(
      for: NSPredicate(format: "exists == false"),
      evaluatedWith: app.staticTexts["Reply that must remain"])
    waitForExpectations(timeout: 5)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["photo-feed-comments-1"].label, "댓글 2개")
  }

  @MainActor
  func testLikeRequiresLoginAndSynchronizesAcrossDetailAndFeed() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    let like = app.buttons["photo-detail-like"]
    for _ in 0..<4 where !like.isHittable { app.swipeUp() }
    XCTAssertTrue(like.waitForExistence(timeout: 5))
    like.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-logout"].waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()
    XCTAssertTrue(like.waitForExistence(timeout: 5))
    XCTAssertEqual(like.value as? String, "1개")
    like.tap()
    let liked = NSPredicate(format: "label == %@ AND value == %@", "좋아요 취소", "2개")
    expectation(for: liked, evaluatedWith: like)
    waitForExpectations(timeout: 5)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Photo liked"
    capture.lifetime = .keepAlways
    add(capture)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["photo-feed-like-1"].exists)
    XCTAssertEqual(app.staticTexts["photo-feed-like-1"].label, "좋아요 2개")
    card.tap()
    for _ in 0..<4 where !like.isHittable { app.swipeUp() }
    XCTAssertEqual(like.value as? String, "2개")
    like.tap()
    expectation(
      for: NSPredicate(format: "label == %@ AND value == %@", "좋아요", "1개"), evaluatedWith: like)
    waitForExpectations(timeout: 5)
  }

  @MainActor
  func testAccountLoginFailureSuccessProfileAndLogout() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    XCTAssertEqual(account.value as? String, "로그아웃 상태")
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    let login = app.buttons["account-signin"]
    XCTAssertFalse(login.isEnabled)
    XCTAssertTrue(login.isHittable)
    XCTAssertGreaterThan(app.buttons["account-close"].frame.minY, app.frame.height * 0.4)
    let loginCapture = XCTAttachment(screenshot: app.screenshot())
    loginCapture.name = "Compact login material"
    loginCapture.lifetime = .keepAlways
    add(loginCapture)
    email.tap()
    email.typeText("photo@example.com")
    let password = app.secureTextFields["account-password"]
    password.tap()
    password.typeText("wrong-password")
    login.tap()
    XCTAssertTrue(
      app.staticTexts["로그인하지 못했어요. 이메일·비밀번호와 네트워크 연결을 확인해 주세요."].waitForExistence(timeout: 5))
    password.tap()
    password.typeText("test-password")
    login.tap()
    XCTAssertTrue(app.staticTexts["테스트 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["account-logout"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Account signed in"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["account-close"].tap()
    XCTAssertTrue(account.waitForExistence(timeout: 5))
    XCTAssertEqual(account.value as? String, "로그인 상태")
    account.tap()
    app.buttons["내 공개 프로필"].tap()
    XCTAssertTrue(app.navigationBars["사진가"].waitForExistence(timeout: 5))
    XCTAssertLessThan(app.navigationBars["사진가"].frame.minY, app.frame.height * 0.3)
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["account-logout"].tap()
    app.buttons.matching(
      NSPredicate(format: "label == %@ AND identifier != %@", "로그아웃", "account-logout")
    ).firstMatch.tap()
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()
    XCTAssertTrue(account.waitForExistence(timeout: 5))
  }

  @MainActor
  func testGoogleLoginPublishesAccountAndProfileEntry() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-google"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let google = app.buttons["account-google-signin"]
    XCTAssertTrue(google.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(google.frame.height, 44)
    google.tap()
    XCTAssertTrue(app.staticTexts["Google 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["account-logout"].exists)
    app.buttons["account-close"].tap()
    XCTAssertEqual(account.value as? String, "로그인 상태")
  }

  @MainActor
  func testAccountSheetDarkAndLargeText() throws {
    for mode in ["--ui-test-dark", "--ui-test-large-text"] {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-viewer", mode]
      app.launch()
      let account = app.buttons["photo-feed-account"]
      XCTAssertTrue(account.waitForExistence(timeout: 10))
      account.tap()
      XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
      let close = app.buttons["account-close"]
      if mode == "--ui-test-large-text" {
        XCTAssertLessThan(close.frame.minY, app.frame.height * 0.3)
      } else {
        XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.4)
      }
      let capture = XCTAttachment(screenshot: app.screenshot())
      capture.name = "Account sheet " + mode
      capture.lifetime = .keepAlways
      add(capture)
      close.tap()
      XCTAssertTrue(account.waitForExistence(timeout: 5))
    }
  }

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
  func testPhotographerRetryAndPhotoNavigation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()
    let writer = app.buttons["photo-detail-photographer"]
    XCTAssertTrue(writer.waitForExistence(timeout: 5))
    writer.tap()
    let retry = app.buttons["photographer-retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    retry.tap()
    XCTAssertTrue(app.staticTexts["photographer-name"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.otherElements["photographer-stat-작품"].value as? String, "24")
    XCTAssertEqual(app.otherElements["photographer-stat-사진"].value as? String, "58")
    XCTAssertEqual(app.otherElements["photographer-stat-받은 좋아요"].value as? String, "132")
    let badge = app.buttons["photographer-badge-sensta-app"]
    XCTAssertTrue(badge.waitForExistence(timeout: 5))
    badge.tap()
    XCTAssertTrue(app.staticTexts["SENSTA 앱으로 사진을 공유한 사용자입니다."].waitForExistence(timeout: 5))
    app.buttons["닫기"].tap()
    let photo = app.buttons.matching(identifier: "photographer-photo").firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Photographer recent works"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    if !photo.isHittable { app.swipeUp(velocity: .slow) }
    photo.tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.staticTexts["photographer-name"].waitForExistence(timeout: 5))
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
