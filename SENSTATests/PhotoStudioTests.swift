import Foundation
import Testing

@testable import SENSTA

private let studioBaseURL = URL(string: "https://sensta.me/goapi/")!
private let studioUser = AccountUser(
  uid: 7, name: "사진가", id: "photo@example.com", blocked: false)
private let studioTokens = AccountTokens(token: "studio-access", refresh: "studio-refresh")

@MainActor
private final class StudioTokenStore: AccountTokenStoring {
  var tokens: AccountTokens?
  func read() throws -> AccountTokens? { tokens }
  func save(_ tokens: AccountTokens) throws { self.tokens = tokens }
  func clear() throws { tokens = nil }
}

private actor StudioAccountStub: AccountServing {
  private(set) var requests: [URLRequest] = []

  func data(for request: URLRequest) async throws -> Data {
    requests.append(request)
    return Data(
      #"{"success":true,"error":"","code":0,"result":{"summary":{"postCount":2,"photoCount":5,"viewCount":61,"likeCount":4,"commentCount":3},"posts":{"page":1,"limit":20,"totalCount":2,"hasNext":false,"items":[{"uid":101,"title":"비밀의 빛","cover":"/upload/thumbnails/2026/09/f101.webp","submitted":1788600000000,"modified":1788600001000,"status":2,"imageCount":3,"hit":41,"like":3,"comment":2}]}}}"#
        .utf8)
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (studioUser, studioTokens)
  }
  func load(token: String) async throws -> AccountUser { studioUser }
  func refresh(_ refresh: String) async throws -> AccountTokens { studioTokens }
  func logout(token: String) async throws {}
}

private actor StudioPageStub: PhotoStudioServing {
  private var secondPageAttempts = 0
  private var failNext = false

  func failNextRequest() { failNext = true }

  func fetchPage(_ page: Int, sort: PhotoStudioSort) async throws -> PhotoStudioPage {
    if failNext {
      failNext = false
      throw NuboAPIError.networkUnavailable
    }
    let summary = PhotoStudioSummary(
      postCount: sort == .views ? 1 : 3, photoCount: sort == .views ? 2 : 5,
      viewCount: 61, likeCount: 4, commentCount: 3)
    if sort == .views {
      return PhotoStudioPage(
        summary: summary, page: 1, totalCount: 1, hasNext: false,
        posts: [makePost(id: 9, title: "가장 많이 본 사진")])
    }
    if page == 2 {
      secondPageAttempts += 1
      if secondPageAttempts == 1 { throw NuboAPIError.timedOut }
      return PhotoStudioPage(
        summary: summary, page: 2, totalCount: 3, hasNext: false,
        posts: [makePost(id: 2, title: "중복"), makePost(id: 3, title: "세 번째")])
    }
    return PhotoStudioPage(
      summary: summary, page: 1, totalCount: 3, hasNext: true,
      posts: [makePost(id: 1, title: "첫 번째"), makePost(id: 2, title: "두 번째")])
  }

  private func makePost(id: Int, title: String) -> PhotoStudioPost {
    PhotoStudioPost(
      id: id, title: title, coverURL: nil, submitted: .now, modified: .now,
      isPrivate: id == 2, imageCount: 1, viewCount: id, likeCount: 0, commentCount: 0)
  }
}

struct PhotoStudioContractTests {
  @Test
  func requestUsesAuthenticatedUserScopeAndWhitelistedSort() throws {
    let request = try PhotoStudioEndpoint.request(
      baseURL: studioBaseURL, page: 2, sort: .comments)
    #expect(request.url?.path == "/goapi/board/my/studio")
    #expect(
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
        URLQueryItem(name: "id", value: "photo"),
        URLQueryItem(name: "page", value: "2"),
        URLQueryItem(name: "limit", value: "20"),
        URLQueryItem(name: "sort", value: "comments"),
      ])
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.url?.query?.contains("userUid") == false)
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoStudioEndpoint.request(baseURL: studioBaseURL, page: 0, sort: .recent)
    }
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoStudioEndpoint.request(
        baseURL: studioBaseURL, page: 1, limit: 51, sort: .recent)
    }
  }

  @Test
  func responseMapsPrivateWorkCountsDateAndLocalThumbnail() throws {
    let data = Data(
      #"{"success":true,"error":"","code":0,"result":{"summary":{"postCount":2,"photoCount":5,"viewCount":61,"likeCount":4,"commentCount":3},"posts":{"page":1,"limit":20,"totalCount":2,"hasNext":false,"items":[{"uid":101,"title":"비밀의 빛","cover":"./upload/thumbnails/2026/09/f101.webp","submitted":1788600000000,"modified":1788600001000,"status":2,"imageCount":3,"hit":41,"like":3,"comment":2},{"uid":102,"title":"외부 표지 차단","cover":"https://attacker.example/cover.webp","submitted":1788600000000,"modified":1788600001000,"status":0,"imageCount":2,"hit":20,"like":1,"comment":1}]}}}"#
        .utf8)
    let page = try JSONDecoder().decode(PhotoStudioResponseDTO.self, from: data).makePage(
      apiBaseURL: studioBaseURL, requestedPage: 1, requestedLimit: 20)
    #expect(
      page.summary
        == PhotoStudioSummary(
          postCount: 2, photoCount: 5, viewCount: 61, likeCount: 4, commentCount: 3))
    #expect(page.posts.map(\.id) == [101, 102])
    #expect(page.posts[0].isPrivate)
    #expect(page.posts[0].imageCount == 3)
    #expect(
      page.posts[0].coverURL?.absoluteString
        == "https://sensta.me/upload/thumbnails/2026/09/f101.webp")
    #expect(page.posts[1].coverURL == nil)
    #expect(page.posts[0].submitted.timeIntervalSince1970 == 1_788_600_000)
  }

  @Test
  func responseRejectsMismatchedPageAndUnsafeValues() throws {
    let mismatched = Data(
      #"{"success":true,"error":"","code":0,"result":{"summary":{"postCount":1,"photoCount":1,"viewCount":0,"likeCount":0,"commentCount":0},"posts":{"page":2,"limit":20,"totalCount":1,"hasNext":false,"items":[]}}}"#
        .utf8)
    let response = try JSONDecoder().decode(PhotoStudioResponseDTO.self, from: mismatched)
    #expect(throws: NuboAPIError.malformedResponse) {
      try response.makePage(
        apiBaseURL: studioBaseURL, requestedPage: 1, requestedLimit: 20)
    }

    let invalidStatus = Data(
      #"{"success":true,"error":"","code":0,"result":{"summary":{"postCount":1,"photoCount":1,"viewCount":0,"likeCount":0,"commentCount":0},"posts":{"page":1,"limit":20,"totalCount":1,"hasNext":false,"items":[{"uid":1,"title":"삭제글","cover":"","submitted":0,"modified":0,"status":3,"imageCount":1,"hit":0,"like":0,"comment":0}]}}}"#
        .utf8)
    let invalidResponse = try JSONDecoder().decode(
      PhotoStudioResponseDTO.self, from: invalidStatus)
    #expect(throws: NuboAPIError.malformedResponse) {
      try invalidResponse.makePage(
        apiBaseURL: studioBaseURL, requestedPage: 1, requestedLimit: 20)
    }
  }

  @MainActor @Test
  func accountServiceAddsBearerWithoutAcceptingCallerUserID() async throws {
    let stub = StudioAccountStub()
    let account = AccountSession(
      service: stub, store: StudioTokenStore(), apiBaseURL: studioBaseURL)
    await account.signin(email: studioUser.id, password: "password")
    let page = try await AccountPhotoStudioService(account: account).fetchPage(1, sort: .recent)
    #expect(page.posts.first?.id == 101)
    let requests = await stub.requests
    #expect(requests.count == 1)
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer studio-access")
    #expect(requests[0].url?.query?.contains("userUid") == false)
  }
}

struct PhotoStudioModelTests {
  @MainActor @Test
  func preservesWorksAcrossPagingAndRefreshFailuresThenSwitchesSort() async {
    let service = StudioPageStub()
    let model = PhotoStudioModel(service: service)
    await model.loadIfNeeded()
    #expect(model.posts.map(\.id) == [1, 2])
    #expect(model.summary?.photoCount == 5)
    #expect(model.hasNext)

    await model.loadMore()
    #expect(model.posts.map(\.id) == [1, 2])
    #expect(model.loadMoreError != nil)
    await model.loadMore()
    #expect(model.posts.map(\.id) == [1, 2, 3])
    #expect(!model.hasNext)

    await model.selectSort(.views)
    #expect(model.selectedSort == .views)
    #expect(model.posts.map(\.id) == [9])
    #expect(model.summary?.postCount == 1)

    await service.failNextRequest()
    await model.refresh()
    #expect(model.posts.map(\.id) == [9])
    #expect(model.error != nil)
  }
}
