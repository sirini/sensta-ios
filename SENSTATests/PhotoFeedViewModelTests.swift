import Foundation
import Testing

@testable import SENSTA

@MainActor
struct PhotoFeedViewModelTests {
  @Test
  func loadsPosts() async {
    let post = makePost()
    let model = PhotoFeedViewModel(
      service: SuccessfulPhotoFeedService(page: PhotoFeedPage(totalPostCount: 1, posts: [post]))
    )

    await model.loadIfNeeded()

    #expect(model.state == .loaded([post]))
  }

  @Test
  func presentsEmptyState() async {
    let model = PhotoFeedViewModel(
      service: SuccessfulPhotoFeedService(page: PhotoFeedPage(totalPostCount: 0, posts: []))
    )

    await model.loadIfNeeded()

    #expect(model.state == .empty)
  }

  @Test
  func presentsErrorAndRetries() async {
    let service = RetryPhotoFeedService(page: PhotoFeedPage(totalPostCount: 1, posts: [makePost()]))
    let model = PhotoFeedViewModel(service: service)

    await model.loadIfNeeded()
    guard case .failed(let message) = model.state else {
      Issue.record("첫 요청은 오류 상태여야 합니다.")
      return
    }
    #expect(message == "인터넷 연결을 확인한 뒤 다시 시도해 주세요.")

    await model.retry()

    guard case .loaded(let posts) = model.state else {
      Issue.record("재시도 후 게시글을 표시해야 합니다.")
      return
    }
    #expect(posts.map(\.id) == [101])
    #expect(await service.attemptCount == 2)
  }

  @Test
  func failedRefreshPreservesPhotosAndCanRetry() async {
    let page = PhotoFeedPage(totalPostCount: 1, posts: [makePost()])
    let model = PhotoFeedViewModel(service: RefreshPhotoFeedService(page: page))
    await model.loadIfNeeded()
    await model.refresh()
    #expect(model.state == .loaded(page.posts))
    #expect(model.refreshError != nil)
    await model.refresh()
    #expect(model.state == .loaded(page.posts))
    #expect(model.refreshError == nil)
  }

  @Test
  func cancelledLoadReturnsToIdleAndCanLoadAgain() async {
    let model = PhotoFeedViewModel(service: CancelledPhotoFeedService())
    await model.loadIfNeeded()
    #expect(model.state == .idle)
    #expect(model.refreshError == nil)
  }

  @Test
  func appendsUniquePhotosAndStopsAtEnd() async {
    let first = makePost(id: 101)
    let second = makePost(id: 102)
    let service = ScriptedFeedService([
      .success(PhotoFeedPage(totalPostCount: 3, posts: [first], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 3, posts: [first, second])),
    ])
    let model = PhotoFeedViewModel(service: service)
    await model.loadIfNeeded()
    await model.loadMoreIfNeeded(currentPostID: first.id)
    await model.loadMore()
    #expect(model.state == .loaded([first, second]))
    #expect(!model.hasMorePages)
    #expect(await service.pages == [1, 2])
  }

  @Test
  func skipsFilteredAndDuplicateOnlyPages() async {
    let first = makePost(id: 101)
    let second = makePost(id: 102)
    let service = ScriptedFeedService([
      .success(PhotoFeedPage(totalPostCount: 5, posts: [], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 5, posts: [first], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 5, posts: [first], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 5, posts: [], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 5, posts: [second])),
    ])
    let model = PhotoFeedViewModel(service: service)
    await model.loadIfNeeded()
    #expect(model.state == .loaded([first]))
    await model.loadMore()
    #expect(model.state == .loaded([first, second]))
    #expect(await service.pages == [1, 2, 3, 4, 5])
  }

  @Test
  func failedPageKeepsPhotosAndRetriesSamePageOnlyOnRequest() async {
    let first = makePost(id: 101)
    let second = makePost(id: 102)
    let service = ScriptedFeedService([
      .success(PhotoFeedPage(totalPostCount: 2, posts: [first], hasMorePages: true)),
      .failure(.networkUnavailable),
      .success(PhotoFeedPage(totalPostCount: 2, posts: [second])),
    ])
    let model = PhotoFeedViewModel(service: service)
    await model.loadIfNeeded()
    await model.loadMore()
    #expect(model.state == .loaded([first]))
    #expect(model.loadMoreError != nil)
    #expect(!model.isLoadingMore)
    await model.loadMoreIfNeeded(currentPostID: first.id)
    #expect(await service.pages == [1, 2])
    await model.loadMore()
    #expect(await service.pages == [1, 2, 2])
    #expect(model.state == .loaded([first, second]))
    #expect(model.loadMoreError == nil)
  }

  @Test
  func refreshResetsPagination() async {
    let first = makePost(id: 101)
    let second = makePost(id: 102)
    let service = ScriptedFeedService([
      .success(PhotoFeedPage(totalPostCount: 2, posts: [first], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 2, posts: [second])),
      .success(PhotoFeedPage(totalPostCount: 2, posts: [second], hasMorePages: true)),
      .success(PhotoFeedPage(totalPostCount: 2, posts: [first])),
    ])
    let model = PhotoFeedViewModel(service: service)
    await model.loadIfNeeded()
    await model.loadMore()
    await model.refresh()
    #expect(model.state == .loaded([second]))
    await model.loadMore()
    #expect(await service.pages == [1, 2, 1, 2])
    #expect(model.state == .loaded([second, first]))
  }

  @Test
  func refreshSupersedesInFlightPageAndPreventsDuplicateRequests() async {
    let first = makePost(id: 101)
    let old = makePost(id: 102)
    let fresh = makePost(id: 103)
    let service = SuspendedFeedService(first: first, old: old, fresh: fresh)
    let model = PhotoFeedViewModel(service: service)
    await model.loadIfNeeded()
    let paging = Task { await model.loadMore() }
    await service.waitForPageRequest()
    await model.loadMore()
    #expect(await service.pages == [1, 2])
    await model.refresh()
    await service.finishOldPage()
    await paging.value
    #expect(model.state == .loaded([fresh]))
    #expect(!model.isLoadingMore)
    #expect(!model.hasMorePages)
    #expect(await service.pages == [1, 2, 1])
  }

  private func makePost(id: Int = 101) -> PhotoPost {
    PhotoPost(
      id: id,
      title: "테스트 사진",
      content: "",
      submitted: Date(timeIntervalSince1970: 1_788_500_000),
      viewCount: 3,
      coverURL: URL(string: "https://sensta.me/image.webp"),
      commentCount: 1,
      likeCount: 2,
      isLiked: false,
      writer: PhotoPostWriter(id: 42, name: "사진가", profileURL: nil, badgeKeys: [])
    )
  }
}

private struct SuccessfulPhotoFeedService: PhotoFeedServing {
  let page: PhotoFeedPage

  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    self.page
  }
}

private actor RetryPhotoFeedService: PhotoFeedServing {
  let page: PhotoFeedPage
  private(set) var attemptCount = 0

  init(page: PhotoFeedPage) {
    self.page = page
  }

  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    attemptCount += 1
    if attemptCount == 1 {
      throw NuboAPIError.networkUnavailable
    }
    return self.page
  }
}

private actor RefreshPhotoFeedService: PhotoFeedServing {
  let page: PhotoFeedPage
  private var attempts = 0
  init(page: PhotoFeedPage) { self.page = page }
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    attempts += 1
    if attempts == 2 { throw NuboAPIError.networkUnavailable }
    return self.page
  }
}

private struct CancelledPhotoFeedService: PhotoFeedServing {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage { throw CancellationError() }
}

private actor ScriptedFeedService: PhotoFeedServing {
  private var responses: [Result<PhotoFeedPage, NuboAPIError>]
  private(set) var pages: [Int] = []
  init(_ responses: [Result<PhotoFeedPage, NuboAPIError>]) { self.responses = responses }
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    pages.append(page)
    guard !responses.isEmpty else { throw NuboAPIError.invalidRequest }
    return try responses.removeFirst().get()
  }
}

private actor SuspendedFeedService: PhotoFeedServing {
  let first: PhotoPost
  let old: PhotoPost
  let fresh: PhotoPost
  private(set) var pages: [Int] = []
  private var continuation: CheckedContinuation<PhotoFeedPage, Never>?
  private var started: CheckedContinuation<Void, Never>?
  init(first: PhotoPost, old: PhotoPost, fresh: PhotoPost) {
    self.first = first
    self.old = old
    self.fresh = fresh
  }
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    pages.append(page)
    if page == 2 {
      return await withCheckedContinuation { continuation in
        self.continuation = continuation
        started?.resume()
        started = nil
      }
    }
    return PhotoFeedPage(
      totalPostCount: 2,
      posts: [pages.count == 1 ? first : fresh],
      hasMorePages: pages.count == 1
    )
  }
  func waitForPageRequest() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finishOldPage() {
    continuation?.resume(returning: PhotoFeedPage(totalPostCount: 2, posts: [old]))
    continuation = nil
  }
}

@MainActor
struct PhotoExploreModelTests {
  @Test
  func emptyQueryLoadsLatestAndSearchPreservesModeAndPage() async throws {
    let service = ExploreRecordingService()
    _ = try await PhotoSearchResultsService(source: service, keyword: "", option: .aiDescription)
      .fetchPage(2)
    _ = try await PhotoSearchResultsService(source: service, keyword: "빛", option: .aiDescription)
      .fetchPage(3)
    #expect(await service.calls == ["latest:2", "12:빛:3"])
  }

  @Test
  func recentTagsFailureRetriesAndCachesSuccessfulBoard() async {
    let service = ExploreRecordingService()
    let model = PhotoRecentTagsModel(service: service)
    await model.load(boardID: nil)
    #expect(await service.tagCalls == 0)
    await model.load(boardID: 42)
    #expect(model.error != nil)
    #expect(!model.isLoading)
    await model.load(boardID: 42)
    #expect(model.tags.map(\.id) == [42])
    #expect(model.error == nil)
    await model.load(boardID: 42)
    #expect(await service.tagCalls == 2)
    await model.load(boardID: 42, force: true)
    #expect(await service.tagCalls == 3)
  }
}

private actor ExploreRecordingService: PhotoFeedServing {
  private(set) var calls: [String] = []
  private(set) var tagCalls = 0
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    calls.append("latest:\(page)")
    return PhotoFeedPage(totalPostCount: 0, posts: [], boardID: 42)
  }
  func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws -> PhotoFeedPage
  {
    calls.append("\(option.rawValue):\(keyword):\(page)")
    return PhotoFeedPage(totalPostCount: 0, posts: [], boardID: 42)
  }
  func recentTags(boardID: Int) async throws -> [PhotoPostTag] {
    tagCalls += 1
    if tagCalls == 1 { throw NuboAPIError.networkUnavailable }
    return [PhotoPostTag(id: boardID, name: "빛")]
  }
}

@MainActor
struct PhotographerModelTests {
  @Test
  func refreshFailureKeepsPreviouslyLoadedProfile() async {
    let model = PhotographerModel()
    let service = PhotographerRefreshService()
    await model.load(userID: 42, service: service)
    #expect(model.profile?.writer.id == 42)
    await model.load(userID: 42, service: service)
    #expect(model.profile?.writer.id == 42)
    #expect(model.error != nil)
    #expect(!model.isLoading)
  }
}

private actor PhotographerRefreshService: PhotoPostDetailServing {
  private var attempts = 0
  func fetchPost(id: Int) async throws -> PhotoPostDetail { throw NuboAPIError.configuration }
  func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
    attempts += 1
    if attempts > 1 { throw NuboAPIError.networkUnavailable }
    return PhotographerProfile(
      writer: PhotoPostWriter(id: id, name: "사진가", profileURL: nil, badgeKeys: []), signature: "",
      posts: [], unavailableCount: 0)
  }
}
