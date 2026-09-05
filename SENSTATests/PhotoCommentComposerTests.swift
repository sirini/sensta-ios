import Foundation
import Testing

@testable import SENSTA

private let commentBaseURL = URL(string: "https://example.com/goapi/")!

@MainActor private final class CommentTokenStore: AccountTokenStoring {
  func read() throws -> AccountTokens? { AccountTokens(token: "access", refresh: "refresh") }
  func save(_ tokens: AccountTokens) throws {}
  func clear() throws {}
}

private actor CommentWriteStub: AccountServing {
  enum Mode { case success, rejected, uncertain, invalidID, paused }
  let mode: Mode
  var requests: [URLRequest] = []
  var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .success) { self.mode = mode }
  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (try await load(token: ""), AccountTokens(token: "access", refresh: "refresh"))
  }
  func load(token: String) async throws -> AccountUser {
    AccountUser(uid: 7, name: "사진가", id: "photo@example.com", blocked: false)
  }
  func refresh(_ refresh: String) async throws -> AccountTokens {
    throw NuboAPIError.httpStatus(401)
  }
  func logout(token: String) async throws {}
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func data(for request: URLRequest) async throws -> Data {
    requests.append(request)
    if mode == .paused { await withCheckedContinuation { continuation = $0 } }
    if mode == .uncertain { throw NuboAPIError.networkFailure }
    if mode == .rejected { return Data(#"{"success":false,"code":3,"result":null}"#.utf8) }
    return Data(
      (mode == .invalidID
        ? #"{"success":true,"code":0,"result":0}"# : #"{"success":true,"code":0,"result":91}"#).utf8
    )
  }
}

@MainActor struct PhotoCommentComposerTests {
  private func setup(_ service: CommentWriteStub) async -> AccountSession {
    let account = AccountSession(
      service: service, store: CommentTokenStore(), apiBaseURL: commentBaseURL)
    await account.restore()
    return account
  }
  @Test func formMatchesAndroidAndReplyTargetsActualComment() throws {
    for reply in [nil, 32] as [Int?] {
      let request = try PhotoCommentWriteEndpoint.request(
        baseURL: commentBaseURL, boardID: 2, postID: 10,
        content: "  사진 이야기 & + = 🌅\n다음 줄  ", replyID: reply)
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path == (reply == nil ? "/goapi/comment/write" : "/goapi/comment/reply"))
      let body = String(data: request.httpBody!, encoding: .utf8)!
      let fields = Dictionary(
        uniqueKeysWithValues: body.split(separator: "&").map {
          let pair = $0.split(separator: "=", maxSplits: 1)
          return (String(pair[0]), String(pair[1]).removingPercentEncoding!)
        })
      #expect(fields["content"] == "사진 이야기 & + = 🌅\n다음 줄")
      #expect(fields["boardUid"] == "2")
      #expect(fields["postUid"] == "10")
      #expect(fields["replyTargetUid"] == reply.map(String.init))
      #expect(fields["userUid"] == nil)
      #expect(fields.count == (reply == nil ? 3 : 4))
      #expect(!request.httpShouldHandleCookies)
    }
  }
  @Test func minimumUsesTrimmedAndroidUTF16Length() throws {
    let model = PhotoCommentComposerModel()
    model.text = "  123456789  "
    #expect(!model.canSend)
    #expect(!model.hasMinimumLength)
    model.text = "🌅🌅🌅🌅🌅"
    #expect(model.canSend)
    #expect(model.hasMinimumLength)
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoCommentWriteEndpoint.request(
        baseURL: commentBaseURL, boardID: 2, postID: 10, content: "too short", replyID: nil)
    }
  }
  @Test func confirmedReplyClearsDraftAndCountsOnlyOnce() async throws {
    let service = CommentWriteStub()
    let account = await setup(service)
    let model = PhotoCommentComposerModel()
    model.text = "  Thank you for sharing  "
    model.reply = PhotoComment(
      id: 32, replyID: 1, writer: "친구", content: "원문", submitted: .now, likeCount: 0)
    let comment = try #require(await model.send(account: account, boardID: 2, postID: 10))
    #expect(comment.id == 91 && comment.replyID == 32)
    #expect(comment.content == "Thank you for sharing")
    #expect(model.text.isEmpty && model.reply == nil && !model.isSending)
    #expect(
      await service.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer access")
    account.recordComment(id: comment.id, postID: 10, baseline: 4)
    account.recordComment(id: comment.id, postID: 10, baseline: 4)
    #expect(account.commentCounts[10] == 5)
  }
  @Test func rejectionPreservesDraftAndUnknownOutcomeRequiresExplicitRetry() async {
    for mode in [CommentWriteStub.Mode.rejected, .uncertain, .invalidID] {
      let service = CommentWriteStub(mode)
      let account = await setup(service)
      let model = PhotoCommentComposerModel()
      model.text = "A wonderful photograph"
      #expect(await model.send(account: account, boardID: 2, postID: 10) == nil)
      #expect(model.text == "A wonderful photograph")
      #expect(model.error != nil && !model.isSending)
      #expect(model.needsRetryConfirmation == (mode != .rejected))
      if mode != .rejected {
        #expect(await model.send(account: account, boardID: 2, postID: 10) == nil)
        #expect(await service.requests.count == 1)
        _ = await model.send(account: account, boardID: 2, postID: 10, allowRetry: true)
        #expect(await service.requests.count == 2)
      }
    }
  }
  @Test func duplicateSendAndLateLogoutResponseAreIgnored() async {
    let service = CommentWriteStub(.paused)
    let account = await setup(service)
    let model = PhotoCommentComposerModel()
    model.text = "A wonderful photograph"
    let pending = Task { await model.send(account: account, boardID: 2, postID: 10) }
    while await service.requests.isEmpty { await Task.yield() }
    #expect(await model.send(account: account, boardID: 2, postID: 10) == nil)
    #expect(await service.requests.count == 1)
    await account.logout()
    model.reset()
    await service.resume()
    #expect(await pending.value == nil)
    #expect(model.text.isEmpty && model.error == nil && !model.isSending)
  }
}
