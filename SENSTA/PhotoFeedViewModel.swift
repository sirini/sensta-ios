import Foundation
import Observation

@MainActor
@Observable
final class PhotoFeedViewModel {
  enum State: Equatable {
    case idle
    case loading
    case loaded([PhotoPost])
    case empty
    case failed(String)
  }

  private let service: any PhotoFeedServing
  private var requestID: UUID?
  private var fetchTask: Task<PhotoFeedPage, Error>?
  private var nextPage = 1
  private(set) var state: State = .idle
  private(set) var refreshError: String?
  private(set) var loadMoreError: String?
  private(set) var isLoadingMore = false
  private(set) var hasMorePages = false

  init(service: any PhotoFeedServing) {
    self.service = service
  }

  func loadIfNeeded() async {
    guard state == .idle else { return }
    await load(showsLoadingState: true)
  }

  func refresh() async {
    await load(showsLoadingState: false)
  }

  func retry() async {
    await load(showsLoadingState: true)
  }

  func loadMoreIfNeeded(currentPostID: Int) async {
    guard case .loaded(let posts) = state,
      let index = posts.firstIndex(where: { $0.id == currentPostID }),
      index >= posts.count - 3, loadMoreError == nil
    else { return }
    await loadMore()
  }

  func loadMore() async {
    guard requestID == nil, hasMorePages, case .loaded(let previousPosts) = state else { return }
    let id = beginRequest()
    isLoadingMore = true
    loadMoreError = nil
    defer { finishRequest(id) }

    do {
      var pageNumber = nextPage
      var posts = previousPosts
      var seenIDs = Set(posts.map(\.id))
      while true {
        let page = try await fetch(pageNumber)
        guard requestID == id else { return }
        posts += page.posts.filter { seenIDs.insert($0.id).inserted }
        pageNumber += 1
        // 차단되거나 중복된 사진만 있는 페이지는 다음 공개 사진까지 건너뛴다.
        if posts.count > previousPosts.count || !page.hasMorePages {
          nextPage = pageNumber
          hasMorePages = page.hasMorePages
          state = .loaded(posts)
          return
        }
      }
    } catch is CancellationError {
      return
    } catch {
      guard requestID == id else { return }
      loadMoreError = Self.userMessage(for: error)
    }
  }

  private func load(showsLoadingState: Bool) async {
    let previousState = state
    let id = beginRequest()
    refreshError = nil
    if showsLoadingState { state = .loading }
    defer { finishRequest(id) }

    do {
      var pageNumber = 1
      while true {
        let page = try await fetch(pageNumber)
        guard requestID == id else { return }
        var seenIDs = Set<Int>()
        let posts = page.posts.filter { seenIDs.insert($0.id).inserted }
        pageNumber += 1
        if !posts.isEmpty || !page.hasMorePages {
          nextPage = pageNumber
          hasMorePages = page.hasMorePages
          loadMoreError = nil
          state = posts.isEmpty ? .empty : .loaded(posts)
          return
        }
      }
    } catch is CancellationError {
      guard requestID == id else { return }
      state = previousState
    } catch {
      guard requestID == id else { return }
      if case .loaded = previousState, !showsLoadingState {
        state = previousState
        refreshError = Self.userMessage(for: error)
      } else {
        state = .failed(Self.userMessage(for: error))
      }
    }
  }

  private func beginRequest() -> UUID {
    fetchTask?.cancel()
    let id = UUID()
    requestID = id
    isLoadingMore = false
    return id
  }

  private func finishRequest(_ id: UUID) {
    guard requestID == id else { return }
    requestID = nil
    fetchTask = nil
    isLoadingMore = false
  }

  private func fetch(_ page: Int) async throws -> PhotoFeedPage {
    try Task.checkCancellation()
    let task = Task { try await service.fetchPage(page) }
    fetchTask = task
    return try await withTaskCancellationHandler {
      let result = try await task.value
      try Task.checkCancellation()
      return result
    } onCancel: {
      task.cancel()
    }
  }

  private static func userMessage(for error: Error) -> String {
    if let error = error as? NuboAPIError,
      let description = error.errorDescription
    {
      return description
    }
    return "사진을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
  }
}
