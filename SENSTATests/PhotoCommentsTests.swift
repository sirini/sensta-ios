import Foundation
import Testing

@testable import SENSTA

struct PhotoCommentsContractTests {
  @Test
  func buildsAnonymousBoardScopedRequest() throws {
    let request = try PhotoCommentsEndpoint.makeRequest(
      apiBaseURL: #require(URL(string: "https://sensta.me/goapi/")), boardID: 2, postID: 7520,
      page: 3)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(components.path == "/goapi/comment/list")
    #expect(query == ["boardUid": "2", "postUid": "7520", "page": "3", "limit": "30"])
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoCommentsEndpoint.makeRequest(apiBaseURL: url, boardID: 0, postID: 7520, page: 1)
    }
  }

  @Test
  func decodesAndroidCommentContractAndReply() throws {
    let response = try JSONDecoder().decode(PhotoCommentsResponseDTO.self, from: fixture())
    let page = try response.makePage(boardID: 2, postID: 7520, page: 1)
    #expect(page.comments.count == 1)
    #expect(page.comments[0].id == 231)
    #expect(page.comments[0].content == "멋진 사진들이네요!")
    #expect(page.comments[0].submitted == Date(timeIntervalSince1970: 1778822019.491))
    #expect(page.comments[0].writerID == 1)
    #expect(!page.comments[0].isLiked)
    #expect(!page.comments[0].isReply)
    #expect(!page.hasMore)
    #expect(throws: NuboAPIError.malformedResponse) {
      try response.makePage(boardID: 3, postID: 7520, page: 1)
    }
    #expect(throws: NuboAPIError.malformedResponse) {
      try response.makePage(boardID: 2, postID: 999, page: 1)
    }
  }

  @Test
  func filtersNonpublicCommentsWithoutEndingPaginationEarly() throws {
    var json = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    var result = try #require(json["result"] as? [String: Any])
    let comments = try #require(result["comments"] as? [[String: Any]])
    var hidden = comments[0]
    hidden["status"] = 2
    hidden["content"] = "비공개 내용"
    result["comments"] = Array(repeating: hidden, count: 30)
    result["totalCommentCount"] = 31
    json["result"] = result
    let response = try JSONDecoder().decode(
      PhotoCommentsResponseDTO.self,
      from: JSONSerialization.data(withJSONObject: json))
    let page = try response.makePage(boardID: 2, postID: 7520, page: 1)
    #expect(page.comments.isEmpty)
    #expect(page.hasMore)
  }

  @Test
  func preservesPermissionErrorsWithoutResult() throws {
    let response = try JSONDecoder().decode(
      PhotoCommentsResponseDTO.self,
      from: Data(#"{"success":false,"error":"no permission","code":3}"#.utf8))
    #expect(throws: NuboAPIError.server(code: 3, message: "no permission")) {
      try response.makePage(boardID: 2, postID: 7520, page: 1)
    }
  }

  private func fixture() -> Data {
    Data(
      #"""
      {"success":true,"error":"","code":0,"result":{
        "boardUid":2,"sinceUid":0,"totalCommentCount":1,"comments":[{
          "uid":231,"replyUid":231,"postUid":7520,
          "writer":{"uid":1,"name":"사진가","profile":"/profile.webp","signature":""},
          "like":0,"liked":false,"submitted":1778822019491,"modified":0,"status":0,
          "content":"<p>멋진 사진들이네요!</p>"
        }]}}
      """#.utf8)
  }
}

@MainActor
struct PhotoCommentsViewModelTests {
  @Test
  func failedPageRetriesAndAppendsOnlyUniqueComments() async {
    let first = makeComment(1)
    let reply = makeComment(2)
    let service = CommentsScript([
      .success(PhotoCommentsPage(comments: [first], hasMore: true)),
      .failure(.networkUnavailable),
      .success(PhotoCommentsPage(comments: [first, reply], hasMore: false)),
    ])
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    await model.loadIfNeeded()
    await model.loadMore()
    #expect(model.comments == [first])
    #expect(model.error != nil)
    await model.retry()
    #expect(model.comments == [first, reply])
    #expect(model.comments[1].isReply)
    #expect(!model.hasMore)
    await model.loadMore()
    #expect(await service.pages == [1, 2, 2])
  }

  @Test
  func refreshFailurePreservesCommentsAndRetriesRefresh() async {
    let first = makeComment(1)
    let service = CommentsScript([
      .success(PhotoCommentsPage(comments: [first], hasMore: true)),
      .failure(.networkUnavailable),
      .success(PhotoCommentsPage(comments: [], hasMore: false)),
    ])
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    await model.loadIfNeeded()
    await model.refresh()
    #expect(model.comments == [first])
    await model.retry()
    #expect(await service.pages == [1, 1, 1])
    #expect(model.comments.isEmpty)
    #expect(model.hasLoaded)
    #expect(!model.isLoading)
  }

  @Test
  func skipsFilteredPages() async {
    let service = CommentsScript([
      .success(PhotoCommentsPage(comments: [], hasMore: true)),
      .success(PhotoCommentsPage(comments: [makeComment(1)], hasMore: false)),
    ])
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    await model.loadIfNeeded()
    #expect(model.comments.count == 1)
    #expect(await service.pages == [1, 2])
  }

  @Test
  func initialFailureCanRetry() async {
    let service = CommentsScript([
      .failure(.networkUnavailable),
      .success(PhotoCommentsPage(comments: [], hasMore: false)),
    ])
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    await model.loadIfNeeded()
    #expect(!model.hasLoaded)
    await model.retry()
    #expect(model.hasLoaded)
    #expect(model.error == nil)
    #expect(await service.pages == [1, 1])
  }

  @Test func confirmedCommentSurvivesStaleRefreshAndPaginationThenUsesServerContent() async {
    let first = makeComment(1)
    let local = makeComment(3)
    let canonical = PhotoComment(
      id: 3, replyID: 1, writer: "사진가", content: "서버 정제 내용", submitted: .distantPast, likeCount: 0)
    let service = CommentsScript([
      .success(PhotoCommentsPage(comments: [first], hasMore: true)),
      .success(PhotoCommentsPage(comments: [makeComment(2)], hasMore: false)),
      .failure(.networkUnavailable),
      .success(PhotoCommentsPage(comments: [first], hasMore: true)),
      .success(PhotoCommentsPage(comments: [canonical], hasMore: false)),
    ])
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    await model.loadIfNeeded()
    model.appendConfirmed(local)
    await model.loadMore()
    #expect(model.comments.map(\.id) == [1, 2, 3])
    await model.refresh()
    #expect(model.comments.contains(local))
    await model.retry()
    #expect(model.comments.map(\.id) == [1, 3])
    await model.loadMore()
    #expect(model.comments == [first, canonical])
  }

  @Test func writeDuringInitialLoadQueuesRefreshAndKeepsConfirmedComment() async {
    let service = PausedCommentsScript()
    let model = PhotoCommentsViewModel(boardID: 2, postID: 7520, service: service)
    let pending = Task { await model.loadIfNeeded() }
    while await service.calls == 0 { await Task.yield() }
    let local = makeComment(3)
    model.appendConfirmed(local)
    await model.refresh()
    await service.resume()
    await pending.value
    while await service.calls < 2 || model.isLoading { await Task.yield() }
    #expect(model.comments == [local])
    #expect(await service.calls == 2)
  }

  private func makeComment(_ id: Int) -> PhotoComment {
    PhotoComment(
      id: id, replyID: 1, writer: "사진가", content: "사진 이야기", submitted: .distantPast, likeCount: 0)
  }
}

private actor CommentsScript: PhotoCommentsServing {
  private var responses: [Result<PhotoCommentsPage, NuboAPIError>]
  private(set) var pages: [Int] = []
  init(_ responses: [Result<PhotoCommentsPage, NuboAPIError>]) { self.responses = responses }
  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
    pages.append(page)
    guard !responses.isEmpty else { throw NuboAPIError.invalidRequest }
    return try responses.removeFirst().get()
  }
}

private actor PausedCommentsScript: PhotoCommentsServing {
  var calls = 0
  var continuation: CheckedContinuation<Void, Never>?
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
    calls += 1
    if calls == 1 { await withCheckedContinuation { continuation = $0 } }
    return PhotoCommentsPage(comments: [], hasMore: false)
  }
}

private let commentLikeBaseURL = URL(string: "https://example.com/goapi/")!

@MainActor private final class CommentLikeTokenStore: AccountTokenStoring {
  var value: AccountTokens? = AccountTokens(token: "access", refresh: "refresh")
  func read() throws -> AccountTokens? { value }
  func save(_ tokens: AccountTokens) throws { value = tokens }
  func clear() throws { value = nil }
}

private actor CommentLikeServiceStub: AccountServing {
  enum Mode { case normal, uncertain, paused }
  let mode: Mode
  var liked = false
  var mutationCount = 0
  var requests: [URLRequest] = []
  var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .normal) { self.mode = mode }
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
    if request.httpMethod == "PATCH" {
      mutationCount += 1
      if mode == .paused { await withCheckedContinuation { continuation = $0 } }
      if mode == .uncertain { throw NuboAPIError.networkFailure }
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      liked = body["liked"] as! Bool
      return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
    }
    let comment: [String: Any] = [
      "uid": 31, "replyUid": 31, "postUid": 10,
      "writer": ["uid": 8, "name": "다른 사진가", "profile": "", "signature": ""],
      "like": liked ? 3 : 2, "liked": liked, "submitted": 1_778_000_000_000 as Int64,
      "modified": 0, "status": 0, "content": "빛이 참 아름답습니다.",
    ]
    return try JSONSerialization.data(withJSONObject: [
      "success": true, "error": "", "code": 0,
      "result": ["boardUid": 2, "totalCommentCount": 1, "comments": [comment]],
    ])
  }
}

@MainActor struct PhotoCommentLikeTests {
  private func setup(_ service: CommentLikeServiceStub) async -> AccountSession {
    let account = AccountSession(
      service: service, store: CommentLikeTokenStore(), apiBaseURL: commentLikeBaseURL)
    await account.restore()
    return account
  }

  @Test func requestMatchesAndroidJSONContract() throws {
    let request = try PhotoCommentLikeEndpoint.request(
      baseURL: commentLikeBaseURL, boardID: 2, commentID: 31, liked: true)
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(request.url?.path == "/goapi/comment/like")
    #expect(request.httpMethod == "PATCH")
    #expect(body.count == 3)
    #expect(body["boardUid"] as? Int == 2)
    #expect(body["commentUid"] as? Int == 31)
    #expect(body["liked"] as? Bool == true)
    #expect(body["userUid"] == nil)
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoCommentLikeEndpoint.request(
        baseURL: commentLikeBaseURL, boardID: 2, commentID: 0, liked: true)
    }
  }

  @Test func authenticatedListDrivesLikeAndUnlike() async {
    let service = CommentLikeServiceStub()
    let account = await setup(service)
    let model = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    model.accountChanged()
    await model.refresh(account: account)
    #expect(model.hasPersonalizedState(for: account))
    #expect(model.comments.first?.likeCount == 2)
    #expect(model.comments.first?.isLiked == false)
    await model.toggleLike(commentID: 31, account: account)
    #expect(model.comments.first?.likeCount == 3)
    #expect(model.comments.first?.isLiked == true)
    model.accountChanged()
    #expect(!model.hasPersonalizedState(for: account))
    #expect(model.comments.first?.isLiked == false)
    await model.refresh(account: account)
    #expect(model.comments.first?.isLiked == true)
    await model.toggleLike(commentID: 31, account: account)
    #expect(model.comments.first?.likeCount == 2)
    #expect(model.comments.first?.isLiked == false)
    #expect(await service.mutationCount == 2)
    #expect(
      await service.requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer access"
      })
  }

  @Test func uncertainResultBlocksAnotherToggleUntilReload() async {
    let service = CommentLikeServiceStub(.uncertain)
    let account = await setup(service)
    let model = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await model.refresh(account: account)
    await model.toggleLike(commentID: 31, account: account)
    #expect(model.comments.first?.likeCount == 2)
    #expect(model.likeErrors[31] != nil)
    await model.toggleLike(commentID: 31, account: account)
    #expect(await service.mutationCount == 1)
    await model.refresh(account: account)
    #expect(model.likeErrors[31] == nil)
    await model.toggleLike(commentID: 31, account: account)
    #expect(await service.mutationCount == 2)
  }

  @Test func duplicateTapAndLateLogoutResponseDoNotChangeComment() async {
    let service = CommentLikeServiceStub(.paused)
    let account = await setup(service)
    let model = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await model.refresh(account: account)
    let pending = Task { await model.toggleLike(commentID: 31, account: account) }
    while await service.mutationCount == 0 { await Task.yield() }
    await model.toggleLike(commentID: 31, account: account)
    #expect(await service.mutationCount == 1)
    await account.logout()
    model.accountChanged()
    await service.resume()
    await pending.value
    #expect(model.comments.first?.likeCount == 2)
    #expect(model.comments.first?.isLiked == false)
  }
}

private actor CommentManagementServiceStub: AccountServing {
  enum Mode { case normal, rejectedModify, uncertainRemove, pausedModify }
  let mode: Mode
  var rootContent = "원래 댓글 내용입니다."
  var hasReply = true
  var mutationCount = 0
  var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .normal) { self.mode = mode }
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
    if request.httpMethod == "PATCH" {
      mutationCount += 1
      if mode == .pausedModify { await withCheckedContinuation { continuation = $0 } }
      if mode == .rejectedModify {
        return Data(#"{"success":false,"code":3,"result":null}"#.utf8)
      }
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      rootContent = body["content"] as! String
      return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
    }
    if request.httpMethod == "DELETE" {
      mutationCount += 1
      if mode == .uncertainRemove { throw NuboAPIError.networkFailure }
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      let id = Int(query.first { $0.name == "removeTargetUid" }!.value!)!
      if id == 31 { rootContent = "(deleted)" } else { hasReply = false }
      return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
    }
    var comments: [[String: Any]] = [comment(id: 31, replyID: 31, content: rootContent)]
    if hasReply { comments.append(comment(id: 32, replyID: 31, content: "내 답글 내용입니다.")) }
    return try JSONSerialization.data(withJSONObject: [
      "success": true, "error": "", "code": 0,
      "result": ["boardUid": 2, "totalCommentCount": comments.count, "comments": comments],
    ])
  }
  private func comment(id: Int, replyID: Int, content: String) -> [String: Any] {
    [
      "uid": id, "replyUid": replyID, "postUid": 10,
      "writer": ["uid": 7, "name": "사진가", "profile": "", "signature": ""],
      "like": 0, "liked": false, "submitted": 1_778_000_000_000 as Int64,
      "modified": 0, "status": 0, "content": content,
    ]
  }
}

@MainActor struct PhotoCommentManagementTests {
  private func setup(_ service: CommentManagementServiceStub) async -> AccountSession {
    let account = AccountSession(
      service: service, store: CommentLikeTokenStore(), apiBaseURL: commentLikeBaseURL)
    await account.restore()
    return account
  }

  @Test func modifyAndRemoveRequestsMatchAndroidContracts() throws {
    let modify = try PhotoCommentManagementEndpoint.modifyRequest(
      baseURL: commentLikeBaseURL, boardID: 2, postID: 10, commentID: 31,
      content: "  <script>\"사진\" & '빛'</script>  ")
    let modifyData = try #require(modify.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: modifyData) as? [String: Any])
    #expect(modify.url?.path == "/goapi/comment/modify")
    #expect(modify.httpMethod == "PATCH")
    #expect(body.count == 4)
    #expect(body["boardUid"] as? Int == 2)
    #expect(body["postUid"] as? Int == 10)
    #expect(body["modifyTargetUid"] as? Int == 31)
    #expect(
      body["content"] as? String == "&lt;script&gt;&quot;사진&quot; &amp; &#39;빛&#39;&lt;/script&gt;")
    #expect(body["userUid"] == nil)

    let remove = try PhotoCommentManagementEndpoint.removeRequest(
      baseURL: commentLikeBaseURL, boardID: 2, commentID: 31)
    let removeURL = try #require(remove.url)
    let components = try #require(URLComponents(url: removeURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(remove.url?.path == "/goapi/comment/remove")
    #expect(remove.httpMethod == "DELETE")
    #expect(remove.httpBody == nil)
    #expect(query == ["boardUid": "2", "removeTargetUid": "31"])
  }

  @Test func modifiesOwnCommentAndPreservesConversationWhenRemovingRoot() async {
    let service = CommentManagementServiceStub()
    let account = await setup(service)
    let model = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await model.refresh(account: account)
    #expect(model.comments.count == 2)
    #expect(model.canManage(model.comments[0], account: account))
    #expect(await model.modify(commentID: 31, content: "  <새 댓글> & '빛'  ", account: account))
    #expect(model.comments[0].content == "<새 댓글> & '빛'")
    #expect(await model.remove(commentID: 31, account: account))
    #expect(model.comments[0].content == "삭제된 댓글입니다.")
    #expect(!model.comments[0].canReply)
    #expect(model.comments.count == 2)
    #expect(await model.remove(commentID: 32, account: account))
    #expect(model.comments.map(\.id) == [31])
    #expect(model.totalCount == 1)
    #expect(account.commentCounts[10] == 1)
  }

  @Test func rejectsOtherWriterAndPreservesContentAfterModifyFailure() async {
    let service = CommentManagementServiceStub(.rejectedModify)
    let account = await setup(service)
    let model = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await model.refresh(account: account)
    var other = model.comments[0]
    other.writerID = 99
    #expect(!model.canManage(other, account: account))
    #expect(await model.modify(commentID: 31, content: "수정할 댓글", account: account) == false)
    #expect(model.comments[0].content == "원래 댓글 내용입니다.")
    #expect(model.managementErrors[31] != nil)
  }

  @Test func uncertainRemoveRequiresReloadAndLateLogoutModifyIsIgnored() async {
    let removeService = CommentManagementServiceStub(.uncertainRemove)
    let removeAccount = await setup(removeService)
    let removeModel = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await removeModel.refresh(account: removeAccount)
    #expect(await removeModel.remove(commentID: 32, account: removeAccount) == false)
    #expect(await removeModel.remove(commentID: 32, account: removeAccount) == false)
    #expect(await removeService.mutationCount == 1)
    await removeModel.refresh(account: removeAccount)
    #expect(await removeModel.remove(commentID: 32, account: removeAccount) == false)
    #expect(await removeService.mutationCount == 2)

    let modifyService = CommentManagementServiceStub(.pausedModify)
    let modifyAccount = await setup(modifyService)
    let modifyModel = PhotoCommentsViewModel(
      boardID: 2, postID: 10, service: CommentsScript([]))
    await modifyModel.refresh(account: modifyAccount)
    let pending = Task {
      await modifyModel.modify(commentID: 31, content: "늦게 도착한 수정", account: modifyAccount)
    }
    while await modifyService.mutationCount == 0 { await Task.yield() }
    await modifyAccount.logout()
    modifyModel.accountChanged()
    await modifyService.resume()
    #expect(await pending.value == false)
    #expect(modifyModel.comments[0].content == "원래 댓글 내용입니다.")
  }
}
