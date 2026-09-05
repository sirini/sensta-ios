import Foundation
import Testing

@testable import SENSTA

private let likeBaseURL = URL(string: "https://example.com/goapi/")!
private let originalPair = AccountTokens(token: "old", refresh: "refresh-old")
private let newPair = AccountTokens(token: "new", refresh: "refresh-new")
private final class LikeFixtureMarker {}

@MainActor private final class LikeTokenStore: AccountTokenStoring {
  var value: AccountTokens? = originalPair
  func read() throws -> AccountTokens? { value }
  func save(_ tokens: AccountTokens) throws { value = tokens }
  func clear() throws { value = nil }
}

private actor LikeServiceStub: AccountServing {
  enum Mode { case normal, expired, rejected, pausedRefresh, pausedMutation, uncertainMutation }
  let mode: Mode
  var refreshCount = 0
  var mutationCount = 0
  var requestCount = 0
  var liked = false
  var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .normal) { self.mode = mode }
  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (try await load(token: ""), originalPair)
  }
  func load(token: String) async throws -> AccountUser {
    AccountUser(uid: 7, name: "사진가", id: "photo@example.com", blocked: false)
  }
  func logout(token: String) async throws {}
  func refresh(_ refresh: String) async throws -> AccountTokens {
    refreshCount += 1
    if mode == .pausedRefresh { await withCheckedContinuation { continuation = $0 } }
    if mode == .rejected { throw NuboAPIError.server(code: 4, message: "") }
    return newPair
  }
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func data(for request: URLRequest) async throws -> Data {
    requestCount += 1
    if [.expired, .rejected, .pausedRefresh].contains(mode),
      request.value(forHTTPHeaderField: "Authorization") == "Bearer old"
    {
      throw NuboAPIError.httpStatus(401)
    }
    if request.httpMethod == "PATCH" {
      mutationCount += 1
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      liked = body["liked"] as! Bool
      if mode == .pausedMutation { await withCheckedContinuation { continuation = $0 } }
      if mode == .uncertainMutation { throw NuboAPIError.networkFailure }
      return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
    }
    let url = Bundle(for: LikeFixtureMarker.self).url(
      forResource: "board-view-photo", withExtension: "json")!
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var result = json["result"] as! [String: Any]
    var post = result["post"] as! [String: Any]
    post["liked"] = liked
    post["like"] = liked ? 5 : 4
    result["post"] = post
    json["result"] = result
    return try JSONSerialization.data(withJSONObject: json)
  }
}

@MainActor struct PhotoPostLikesTests {
  private func setup(_ service: LikeServiceStub) async -> (AccountSession, LikeTokenStore) {
    let store = LikeTokenStore()
    let session = AccountSession(service: service, store: store, apiBaseURL: likeBaseURL)
    await session.restore()
    return (session, store)
  }

  @Test func bodyUsesAndroidBoardScopeAndDesiredState() throws {
    let request = try PhotoLikeEndpoint.request(
      baseURL: likeBaseURL, boardID: 2, postID: 101, liked: true)
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(request.url?.path == "/goapi/board/like")
    #expect(request.httpMethod == "PATCH")
    #expect(body.count == 3)
    #expect(body["boardUid"] as? Int == 2)
    #expect(body["postUid"] as? Int == 101)
    #expect(body["liked"] as? Bool == true)
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoLikeEndpoint.request(baseURL: likeBaseURL, boardID: 0, postID: 101, liked: true)
    }
  }

  @Test func loadsPersonalStateAndSynchronizesLikeAndUnlikeCounts() async {
    let (account, _) = await setup(LikeServiceStub())
    await account.postLikes.load(postID: 101, boardID: 2, fallbackCount: 0, account: account)
    #expect(account.postLikes.states[101]?.isReady == true)
    #expect(account.postLikes.counts[101] == 4)
    await account.postLikes.toggle(postID: 101, boardID: 2, account: account)
    #expect(account.postLikes.states[101]?.isLiked == true)
    #expect(account.postLikes.counts[101] == 5)
    await account.postLikes.toggle(postID: 101, boardID: 2, account: account)
    #expect(account.postLikes.states[101]?.isLiked == false)
    #expect(account.postLikes.counts[101] == 4)
  }

  @Test func rejectsMismatchedBoardBeforeEnablingMutation() async {
    let service = LikeServiceStub()
    let (account, _) = await setup(service)
    await account.postLikes.load(postID: 101, boardID: 99, fallbackCount: 0, account: account)
    await account.postLikes.toggle(postID: 101, boardID: 99, account: account)
    #expect(account.postLikes.states[101]?.isReady == false)
    #expect(await service.mutationCount == 0)
  }

  @Test func concurrentExpiredRequestsShareRotationAndSavePair() async throws {
    let service = LikeServiceStub(.pausedRefresh)
    let (account, store) = await setup(service)
    let request = try PhotoPostDetailEndpoint.makeRequest(apiBaseURL: likeBaseURL, postID: 101)
    let first = Task { try await account.sendAuthenticated(request) }
    while await service.refreshCount == 0 { await Task.yield() }
    let second = Task { try await account.sendAuthenticated(request) }
    while await service.requestCount < 2 { await Task.yield() }
    await service.resume()
    _ = try await first.value
    _ = try await second.value
    #expect(await service.refreshCount == 1)
    #expect(store.value == newPair)
  }

  @Test func rejectedRefreshRemovesAuthentication() async throws {
    let service = LikeServiceStub(.rejected)
    let (account, store) = await setup(service)
    let request = try PhotoPostDetailEndpoint.makeRequest(apiBaseURL: likeBaseURL, postID: 101)
    await #expect(throws: NuboAPIError.httpStatus(401)) {
      try await account.sendAuthenticated(request)
    }
    #expect(account.user == nil)
    #expect(store.value == nil)
  }

  @Test func preventsTokenDeliveryOutsideConfiguredAPI() async throws {
    let service = LikeServiceStub()
    let (account, _) = await setup(service)
    for url in [
      "https://other.example/goapi/board/view", "https://example.com/not-goapi/board/view",
    ] {
      await #expect(throws: NuboAPIError.invalidRequest) {
        try await account.sendAuthenticated(URLRequest(url: URL(string: url)!))
      }
    }
    #expect(await service.requestCount == 0)
  }

  @Test func duplicateMutationAndLateLogoutResponseDoNotChangeState() async {
    let service = LikeServiceStub(.pausedMutation)
    let (account, _) = await setup(service)
    await account.postLikes.load(postID: 101, boardID: 2, fallbackCount: 0, account: account)
    let first = Task { await account.postLikes.toggle(postID: 101, boardID: 2, account: account) }
    while await service.mutationCount == 0 { await Task.yield() }
    await account.postLikes.toggle(postID: 101, boardID: 2, account: account)
    #expect(await service.mutationCount == 1)
    await account.logout()
    await service.resume()
    await first.value
    #expect(account.postLikes.states.isEmpty)
    #expect(account.postLikes.counts[101] == 4)
  }

  @Test func logoutDuringRefreshDoesNotResurrectTokens() async throws {
    let service = LikeServiceStub(.pausedRefresh)
    let (account, store) = await setup(service)
    let request = try PhotoPostDetailEndpoint.makeRequest(apiBaseURL: likeBaseURL, postID: 101)
    let pending = Task { try await account.sendAuthenticated(request) }
    while await service.refreshCount == 0 { await Task.yield() }
    await account.logout()
    await service.resume()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(account.user == nil)
    #expect(store.value == nil)
    #expect(await service.requestCount == 1)
  }

  @Test func uncertainMutationRequiresReadBeforeFurtherWrites() async {
    let service = LikeServiceStub(.uncertainMutation)
    let (account, _) = await setup(service)
    await account.postLikes.load(postID: 101, boardID: 2, fallbackCount: 0, account: account)
    await account.postLikes.toggle(postID: 101, boardID: 2, account: account)
    #expect(account.postLikes.states[101]?.isReady == false)
    #expect(account.postLikes.counts[101] == 4)
    await account.postLikes.toggle(postID: 101, boardID: 2, account: account)
    #expect(await service.mutationCount == 1)
    await account.postLikes.load(postID: 101, boardID: 2, fallbackCount: 0, account: account)
    #expect(account.postLikes.states[101]?.isLiked == true)
    #expect(account.postLikes.counts[101] == 5)
  }
}
