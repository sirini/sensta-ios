import XCTest

final class SENSTAUITests: XCTestCase {
  @MainActor
  func testReportsAndBlocksUserAcrossPhotoProfileAndConversation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-safety"]
    app.launch()

    signInForSafetyTest(app)

    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    card.tap()

    let report = app.buttons["photo-detail-report"]
    XCTAssertTrue(report.waitForExistence(timeout: 5))
    report.tap()
    let reason = app.descendants(matching: .any)["user-report-reason"]
    XCTAssertTrue(reason.waitForExistence(timeout: 5))
    reason.tap()
    reason.typeText("inappropriate photo content")
    app.buttons["user-report-submit"].tap()
    let reported = expectation(
      for: NSPredicate(format: "label == %@", "신고 접수됨"), evaluatedWith: report)
    wait(for: [reported], timeout: 5)

    app.buttons["photo-detail-photographer"].tap()
    XCTAssertTrue(app.staticTexts["photographer-name"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["photographer-report"].label, "신고 접수됨")
    app.buttons["photographer-block"].tap()
    app.sheets["이 사용자를 차단할까요?"].buttons["차단"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["photographer-blocked"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["photographer-block"].label, "차단 해제")

    app.buttons["photographer-block"].tap()
    app.sheets["차단을 해제할까요?"].buttons["차단 해제"].tap()
    XCTAssertTrue(app.buttons["photographer-direct-message"].waitForExistence(timeout: 5))
    app.buttons["photographer-direct-message"].tap()
    let menu = app.buttons["direct-message-safety-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    app.buttons["사용자 차단"].tap()
    app.sheets["이 사용자를 차단할까요?"].buttons["차단"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["direct-message-blocked"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.textFields["direct-message-input"].exists)
  }

  @MainActor
  private func signInForSafetyTest(_ app: XCUIApplication) {
    app.buttons["photo-feed-account"].tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-logout"].waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()
  }

  @MainActor
  func testPasswordResetUsesNeutralEmailConfirmation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let loginEmail = app.textFields["account-email"]
    XCTAssertTrue(loginEmail.waitForExistence(timeout: 5))
    loginEmail.tap()
    loginEmail.typeText("photo@example.com")
    app.buttons["account-password-reset"].tap()
    let resetEmail = app.textFields["password-reset-email"]
    XCTAssertTrue(resetEmail.waitForExistence(timeout: 5))
    XCTAssertEqual(resetEmail.value as? String, "photo@example.com")
    app.buttons["password-reset-submit"].tap()
    let completion = app.descendants(matching: .any)["password-reset-complete"]
    XCTAssertTrue(completion.waitForExistence(timeout: 5))
    XCTAssertTrue(completion.label.contains("등록되어 있다면"))
    XCTAssertFalse(completion.label.contains("존재하지"))
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Neutral password reset confirmation"
    capture.lifetime = .keepAlways
    add(capture)
  }

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
    XCTAssertGreaterThan(app.buttons["account-close"].frame.minY, app.frame.height * 0.4)
    let loginCapture = XCTAttachment(screenshot: app.screenshot())
    loginCapture.name = "Compact login material"
    loginCapture.lifetime = .keepAlways
    add(loginCapture)
    let login = app.buttons["account-signin"]
    for _ in 0..<3 where !login.exists { app.swipeUp() }
    XCTAssertTrue(login.exists)
    XCTAssertFalse(login.isEnabled)
    XCTAssertTrue(login.isHittable)
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
  func testMyPhotoStudioPaginatesSortsAndOpensPrivateWork() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    let password = app.secureTextFields["account-password"]
    password.tap()
    password.typeText("test-password")
    app.buttons["account-signin"].tap()

    let studio = app.buttons["account-photo-studio"]
    XCTAssertTrue(studio.waitForExistence(timeout: 5))
    studio.tap()
    XCTAssertTrue(app.navigationBars["내 작품"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["photo-studio-summary"].exists)
    XCTAssertTrue(app.buttons["photo-studio-post-101"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["photo-studio-post-103"].waitForExistence(timeout: 5))
    let listCapture = XCTAttachment(screenshot: app.screenshot())
    listCapture.name = "My studio square preview cards"
    listCapture.lifetime = .keepAlways
    add(listCapture)

    let views = app.buttons["photo-studio-sort-views"]
    XCTAssertTrue(views.isHittable)
    views.tap()
    let privateWork = app.buttons["photo-studio-post-201"]
    XCTAssertTrue(privateWork.waitForExistence(timeout: 5))
    XCTAssertTrue(privateWork.label.contains("가장 많이 본 비공개 사진"))
    XCTAssertTrue((privateWork.value as? String)?.contains("비공개") == true)
    let studioCapture = XCTAttachment(screenshot: app.screenshot())
    studioCapture.name = "My studio summary and private work"
    studioCapture.lifetime = .keepAlways
    add(studioCapture)

    privateWork.tap()
    XCTAssertTrue(app.staticTexts["photo-detail-title"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["photo-detail-title"].label, "가장 많이 본 비공개 사진")
    let detailCapture = XCTAttachment(screenshot: app.screenshot())
    detailCapture.name = "Authenticated private studio detail"
    detailCapture.lifetime = .keepAlways
    add(detailCapture)
  }

  @MainActor
  func testOwnerEditsAndDeletesPhotoFromStudio() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()

    let studio = app.buttons["account-photo-studio"]
    XCTAssertTrue(studio.waitForExistence(timeout: 5))
    studio.tap()
    let views = app.buttons["photo-studio-sort-views"]
    XCTAssertTrue(views.waitForExistence(timeout: 5))
    views.tap()
    let work = app.buttons["photo-studio-post-201"]
    XCTAssertTrue(work.waitForExistence(timeout: 5))
    work.tap()

    let ownerMenu = app.buttons["photo-detail-owner-menu"]
    XCTAssertTrue(ownerMenu.waitForExistence(timeout: 5))
    ownerMenu.tap()
    let edit = app.buttons["photo-detail-edit"]
    XCTAssertTrue(edit.waitForExistence(timeout: 3))
    edit.tap()
    XCTAssertTrue(app.navigationBars["사진 정보 수정"].waitForExistence(timeout: 3))
    let title = app.textFields["photo-edit-title"]
    XCTAssertTrue(title.exists)
    title.tap()
    title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
    title.typeText("수정된 비공개 사진")
    let tags = app.textFields["photo-edit-tags"]
    tags.tap()
    tags.typeText("노을,빛결 ")
    XCTAssertTrue(app.buttons["photo-edit-tag-노을"].waitForExistence(timeout: 3))
    app.buttons["photo-edit-save"].tap()
    let changedTitle = app.staticTexts["photo-detail-title"]
    XCTAssertTrue(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "수정된 비공개 사진"),
            object: changedTitle)
        ], timeout: 5) == .completed)

    XCTAssertTrue(ownerMenu.isHittable)
    ownerMenu.tap()
    let delete = app.buttons["photo-detail-delete"]
    XCTAssertTrue(delete.waitForExistence(timeout: 3))
    delete.tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == %@", "사진 삭제")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 3))
    confirm.tap()

    XCTAssertTrue(app.navigationBars["내 작품"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["photo-studio-post-201"].exists)
  }

  @MainActor
  func testMyPhotoStudioSquareCardsAdaptToLargeText() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-large-text"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    let password = app.secureTextFields["account-password"]
    password.tap()
    password.typeText("test-password")
    app.buttons["account-signin"].tap()
    let studio = app.buttons["account-photo-studio"]
    XCTAssertTrue(studio.waitForExistence(timeout: 5))
    studio.tap()

    XCTAssertTrue(app.navigationBars["내 작품"].waitForExistence(timeout: 5))
    let firstWork = app.buttons["photo-studio-post-101"]
    XCTAssertTrue(firstWork.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(firstWork.frame.minX, app.frame.minX)
    XCTAssertLessThanOrEqual(firstWork.frame.maxX, app.frame.maxX)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "My studio square preview cards with large text"
    capture.lifetime = .keepAlways
    add(capture)
  }

  @MainActor
  func testAchievementCelebrationAcknowledgesQueueAndOpensOwnProfile() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-achievements"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()

    let celebration = app.staticTexts["achievement-name"]
    XCTAssertTrue(celebration.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["SENSTA 앱 포토그래퍼"].exists)
    XCTAssertTrue(app.staticTexts["확인할 새 업적이 2개 있어요"].exists)
    XCTAssertGreaterThanOrEqual(app.buttons["achievement-confirm"].frame.minX, app.frame.minX)
    XCTAssertLessThanOrEqual(app.buttons["achievement-confirm"].frame.maxX, app.frame.maxX)
    let firstCapture = XCTAttachment(screenshot: app.screenshot())
    firstCapture.name = "Achievement celebration queue"
    firstCapture.lifetime = .keepAlways
    add(firstCapture)

    app.buttons["achievement-confirm"].tap()
    XCTAssertTrue(app.staticTexts["첫 발자국"].waitForExistence(timeout: 5))
    app.buttons["achievement-view-profile"].tap()
    XCTAssertTrue(app.navigationBars["사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["photographer-badge-sensta-app"].waitForExistence(timeout: 5))
    XCTAssertFalse(celebration.exists)
    let profileCapture = XCTAttachment(screenshot: app.screenshot())
    profileCapture.name = "Own achievements after acknowledgement"
    profileCapture.lifetime = .keepAlways
    add(profileCapture)
  }

  @MainActor
  func testAchievementCelebrationFitsAccessibilityText() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-viewer", "--ui-test-achievements", "--ui-test-large-text",
    ]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()

    XCTAssertTrue(app.staticTexts["achievement-name"].waitForExistence(timeout: 5))
    let confirm = app.buttons["achievement-confirm"]
    if !confirm.isHittable { app.swipeUp() }
    XCTAssertTrue(confirm.isHittable)
    XCTAssertGreaterThanOrEqual(confirm.frame.minX, app.frame.minX)
    XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX)
    XCTAssertLessThanOrEqual(confirm.frame.maxY, app.frame.maxY)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Achievement celebration with accessibility text"
    capture.lifetime = .keepAlways
    add(capture)
  }

  @MainActor
  func testDirectMessageListLoadsConversationAndPreservesNativeComposer() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-messages", "--ui-test-dark"]
    app.launch()
    signInForMessages(app)

    let messages = app.buttons["account-direct-messages"]
    XCTAssertTrue(messages.waitForExistence(timeout: 5))
    messages.tap()
    XCTAssertTrue(app.navigationBars["1:1 메시지"].waitForExistence(timeout: 5))
    let thread = app.buttons["direct-message-thread-2"]
    XCTAssertTrue(thread.waitForExistence(timeout: 5))
    thread.tap()

    XCTAssertTrue(app.navigationBars["알림 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.descendants(matching: .any)["direct-message-101"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["direct-message-partner"].exists)
    XCTAssertEqual(
      app.descendants(matching: .any)["direct-message-read-102"].label, "읽음")
    let hashtag = app.links["#여름사진"]
    XCTAssertTrue(hashtag.waitForExistence(timeout: 5))
    hashtag.tap()
    XCTAssertTrue(app.navigationBars["탐색"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, "여름사진")
    app.navigationBars["탐색"].buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["알림 사진가"].waitForExistence(timeout: 5))
    let input = app.textFields["direct-message-input"]
    XCTAssertTrue(input.isHittable)
    input.tap()
    input.typeText("새 사진 멋져요")
    let send = app.buttons["direct-message-send"]
    XCTAssertTrue(send.isEnabled)
    send.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["direct-message-103"].waitForExistence(timeout: 5))
    XCTAssertEqual(input.value as? String, "메시지를 입력해 주세요")

    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Native one-to-one message conversation"
    capture.lifetime = .keepAlways
    add(capture)
  }

  @MainActor
  func testMessageNotificationOpensSenderConversation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-messages"]
    app.launch()
    signInForMessages(app)
    app.buttons["account-close"].tap()

    let notifications = app.buttons["photo-feed-notifications"]
    XCTAssertTrue(notifications.waitForExistence(timeout: 5))
    notifications.tap()
    XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout: 5))
    let messageNotification = app.buttons["notification-77"]
    XCTAssertTrue(messageNotification.waitForExistence(timeout: 5))
    messageNotification.tap()
    XCTAssertTrue(app.navigationBars["알림 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.descendants(matching: .any)["direct-message-102"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testLoggedInPhotographerOffersDirectMessage() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-messages", "--ui-test-dark"]
    app.launch()
    signInForMessages(app)
    app.buttons["account-close"].tap()

    let card = app.buttons.matching(identifier: "photo-feed-card").firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    card.tap()
    let writer = app.buttons["photo-detail-photographer"]
    XCTAssertTrue(writer.waitForExistence(timeout: 5))
    writer.tap()
    let message = app.buttons["photographer-direct-message"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    message.tap()
    XCTAssertTrue(app.navigationBars["알림 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.descendants(matching: .any)["direct-message-101"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testEmailSignupVerifiesCodeAndReturnsToLogin() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let signup = app.buttons["account-email-signup"]
    for _ in 0..<3 where !signup.isHittable { app.swipeUp() }
    XCTAssertTrue(signup.isHittable)
    let signin = app.buttons["account-signin"]
    XCTAssertTrue(signin.exists)
    XCTAssertGreaterThanOrEqual(signin.frame.height, 48)
    XCTAssertGreaterThan(signin.frame.width, 300)
    let loginCapture = XCTAttachment(screenshot: app.screenshot())
    loginCapture.name = "Email login and signup actions"
    loginCapture.lifetime = .keepAlways
    add(loginCapture)
    signup.tap()

    let email = app.textFields["signup-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("new@example.com")
    let name = app.textFields["signup-name"]
    name.tap()
    name.typeText("새 사진가")
    app.secureTextFields["signup-password"].tap()
    app.secureTextFields["signup-password"].typeText("Password!1")
    app.secureTextFields["signup-password-confirmation"].tap()
    app.secureTextFields["signup-password-confirmation"].typeText("Password!1")

    let policy = app.buttons["signup-policy"]
    for _ in 0..<4 where !policy.isHittable { app.swipeUp() }
    XCTAssertTrue(policy.isHittable)
    policy.tap()
    XCTAssertEqual(policy.value as? String, "동의함")
    let submit = app.buttons["signup-submit"]
    for _ in 0..<3 where !submit.isHittable { app.swipeUp() }
    submit.tap()

    let code = app.textFields["signup-verification-code"]
    XCTAssertTrue(code.waitForExistence(timeout: 5))
    code.tap()
    code.typeText("123456")
    app.buttons["signup-verify"].tap()
    let returnToLogin = app.buttons["signup-return-to-login"]
    XCTAssertTrue(returnToLogin.waitForExistence(timeout: 5))
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Verified email signup completed"
    capture.lifetime = .keepAlways
    add(capture)
    returnToLogin.tap()
    XCTAssertEqual(app.textFields["account-email"].value as? String, "new@example.com")
  }

  @MainActor
  private func signInForMessages(_ app: XCUIApplication) {
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-direct-messages"].waitForExistence(timeout: 5))
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
    XCTAssertGreaterThan(google.frame.width, app.frame.width * 0.7)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Custom Google sign in button"
    capture.lifetime = .keepAlways
    add(capture)
    google.tap()
    XCTAssertTrue(app.staticTexts["Google 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["account-logout"].exists)
    app.buttons["account-close"].tap()
    XCTAssertEqual(account.value as? String, "로그인 상태")
  }

  @MainActor
  func testAppleLoginUsesNativeFlowContract() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-apple"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let apple = app.buttons["account-apple-signin"]
    XCTAssertTrue(apple.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(apple.frame.height, 44)
    apple.tap()
    XCTAssertTrue(app.staticTexts["Apple 사진가"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["account-apple-linked"].exists)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Apple account linked"
    capture.lifetime = .keepAlways
    add(capture)
  }

  @MainActor
  func testAppleLoginShowsExistingAccountLinkGuidanceBesideButtons() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-viewer", "--ui-test-apple", "--ui-test-apple-link-required",
    ]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let apple = app.buttons["account-apple-signin"]
    XCTAssertTrue(apple.waitForExistence(timeout: 5))
    apple.tap()
    let guidance = app.descendants(matching: .any)["account-error"]
    XCTAssertTrue(guidance.waitForExistence(timeout: 5))
    XCTAssertTrue(guidance.label.contains("로그인한 뒤"))
    XCTAssertLessThan(guidance.frame.minY, app.frame.height * 0.85)
  }

  @MainActor
  func testExistingAccountCanExplicitlyLinkAppleID() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-apple"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    let apple = app.buttons["account-apple-signin"]
    XCTAssertTrue(apple.waitForExistence(timeout: 5))
    apple.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["account-apple-linked"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testAccountDeletionRequiresExactConfirmationAndReturnsToSignedOutState() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-apple"]
    app.launch()
    let account = app.buttons["photo-feed-account"]
    XCTAssertTrue(account.waitForExistence(timeout: 10))
    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()

    let navigation = app.buttons["account-delete-navigation"]
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    navigation.tap()
    let confirmation = app.textFields["account-delete-confirmation"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["account-delete-submit"].isEnabled)
    confirmation.tap()
    confirmation.typeText("DELETE")
    let submit = app.buttons["account-delete-submit"]
    XCTAssertTrue(submit.isEnabled)
    submit.tap()
    app.sheets["계정과 데이터를 영구 삭제할까요?"].buttons["영구 삭제"].tap()

    let completion = app.buttons["account-delete-finish"]
    let signedOut = app.textFields["account-email"]
    XCTAssertTrue(completion.waitForExistence(timeout: 5) || signedOut.waitForExistence(timeout: 2))
  }

  @MainActor
  func testAccountSheetDarkAndLargeText() throws {
    for mode in ["--ui-test-dark", "--ui-test-large-text"] {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-viewer", "--ui-test-google", mode]
      app.launch()
      let account = app.buttons["photo-feed-account"]
      XCTAssertTrue(account.waitForExistence(timeout: 10))
      account.tap()
      XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
      XCTAssertGreaterThanOrEqual(app.buttons["account-google-signin"].frame.height, 44)
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
    let search = app.buttons.matching(identifier: "photo-feed-search").firstMatch
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
    let search = app.buttons.matching(identifier: "photo-feed-search").firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
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
  func testFeedControlsAdaptToProfileNotificationsAndUpload() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-viewer", "--ui-test-upload-editor"]
    app.launch()

    let upload = app.buttons["photo-feed-upload"]
    let account = app.buttons["photo-feed-account"]
    let search = app.buttons.matching(identifier: "photo-feed-search").firstMatch
    let title = app.staticTexts["photo-feed-title-1"]
    XCTAssertTrue(upload.waitForExistence(timeout: 10))
    XCTAssertTrue(account.exists)
    XCTAssertTrue(search.exists)
    XCTAssertTrue(title.exists)
    XCTAssertEqual(search.frame.midY, title.frame.midY, accuracy: 2)
    XCTAssertGreaterThan(search.frame.minY, account.frame.maxY)
    XCTAssertFalse(app.buttons["photo-feed-notifications"].exists)
    XCTAssertFalse(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "조회")).firstMatch
        .exists)
    let writer = app.staticTexts.matching(identifier: "테스트 사진가").firstMatch
    XCTAssertTrue(writer.exists)
    XCTAssertLessThanOrEqual(writer.frame.minX, 22)
    XCTAssertLessThan(writer.frame.maxY, upload.frame.minY)

    account.tap()
    let email = app.textFields["account-email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("photo@example.com")
    app.secureTextFields["account-password"].tap()
    app.secureTextFields["account-password"].typeText("test-password")
    app.buttons["account-signin"].tap()
    XCTAssertTrue(app.buttons["account-logout"].waitForExistence(timeout: 5))
    app.buttons["account-close"].tap()

    XCTAssertEqual(account.label, "내 계정")
    XCTAssertEqual(account.value as? String, "로그인 상태")
    let notifications = app.buttons["photo-feed-notifications"]
    XCTAssertTrue(notifications.waitForExistence(timeout: 5))
    XCTAssertEqual(notifications.value as? String, "새 알림 있음")
    XCTAssertLessThan(account.frame.maxX, notifications.frame.minX)
    notifications.tap()
    XCTAssertTrue(app.navigationBars["알림"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["notification-77"].exists)
    app.buttons["notification-mark-all-read"].tap()
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertEqual(notifications.value as? String, "새 알림 없음")

    upload.tap()
    XCTAssertTrue(app.navigationBars["새 사진"].waitForExistence(timeout: 5))
    let firstPhoto = app.buttons["photo-upload-edit-0"]
    XCTAssertTrue(firstPhoto.waitForExistence(timeout: 5))
    XCTAssertEqual(firstPhoto.value as? String, "원본")
    XCTAssertFalse(app.buttons["photo-upload-submit"].isEnabled)

    firstPhoto.tap()
    XCTAssertTrue(app.navigationBars["사진 편집"].waitForExistence(timeout: 5))
    let cropButton = app.buttons["photo-editor-crop"]
    XCTAssertEqual(cropButton.value as? String, "원본 영역")
    cropButton.tap()
    XCTAssertTrue(app.navigationBars["사진 자르기"].waitForExistence(timeout: 5))
    app.buttons["photo-crop-aspect-portrait45"].tap()
    let cropCapture = XCTAttachment(screenshot: app.screenshot())
    cropCapture.name = "Native photo crop with aspect controls"
    cropCapture.lifetime = .keepAlways
    add(cropCapture)
    app.navigationBars["사진 자르기"].buttons["취소"].tap()
    XCTAssertTrue(app.navigationBars["사진 편집"].waitForExistence(timeout: 5))
    XCTAssertEqual(cropButton.value as? String, "원본 영역")
    cropButton.tap()
    XCTAssertTrue(app.navigationBars["사진 자르기"].waitForExistence(timeout: 5))
    app.buttons["photo-crop-aspect-portrait45"].tap()
    app.buttons["photo-crop-apply"].tap()
    XCTAssertTrue(app.navigationBars["사진 편집"].waitForExistence(timeout: 5))
    XCTAssertEqual(cropButton.value as? String, "자른 영역")
    app.buttons["photo-editor-rotate"].tap()
    app.buttons["photo-editor-mirror"].tap()
    app.buttons["photo-editor-filter-warm"].tap()
    app.sliders["photo-editor-intensity"].adjust(toNormalizedSliderPosition: 0.65)
    let editorCapture = XCTAttachment(screenshot: app.screenshot())
    editorCapture.name = "Native photo rotate mirror and filter editor"
    editorCapture.lifetime = .keepAlways
    add(editorCapture)
    app.buttons["photo-editor-save"].tap()
    XCTAssertTrue(app.navigationBars["새 사진"].waitForExistence(timeout: 10))
    let edited = expectation(
      for: NSPredicate(format: "value == %@", "편집됨"), evaluatedWith: firstPhoto)
    wait(for: [edited], timeout: 5)

    let tagField = app.textFields["photo-upload-tags"]
    for _ in 0..<5 where !tagField.isHittable { app.swipeUp() }
    XCTAssertTrue(tagField.isHittable)
    tagField.tap()
    tagField.typeText("풍경,빛결 ")
    let landscapeTag = app.buttons["photo-upload-tag-풍경"]
    XCTAssertTrue(landscapeTag.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["photo-upload-tag-빛결"].exists)

    tagField.typeText("여름")
    let suggestion = app.buttons["photo-upload-tag-suggestion-31"]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
    for _ in 0..<3 where !suggestion.isHittable { app.swipeUp() }
    XCTAssertTrue(suggestion.isHittable)
    suggestion.tap()
    XCTAssertTrue(app.buttons["photo-upload-tag-여름사진"].waitForExistence(timeout: 5))

    landscapeTag.tap()
    XCTAssertFalse(landscapeTag.exists)
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Native photo upload tag chips and suggestions"
    capture.lifetime = .keepAlways
    add(capture)
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
