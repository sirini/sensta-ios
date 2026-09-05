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
  private var requestInFlight = false
  private(set) var state: State = .idle
  private(set) var refreshError: String?

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

  private func load(showsLoadingState: Bool) async {
    guard !requestInFlight else { return }
    let previousState = state
    requestInFlight = true
    refreshError = nil
    if showsLoadingState {
      state = .loading
    }
    defer { requestInFlight = false }

    do {
      let page = try await service.fetchPage(1)
      try Task.checkCancellation()
      state = page.posts.isEmpty ? .empty : .loaded(page.posts)
    } catch is CancellationError {
      state = previousState
    } catch {
      if case .loaded = previousState, !showsLoadingState {
        state = previousState
        refreshError = Self.userMessage(for: error)
      } else {
        state = .failed(Self.userMessage(for: error))
      }
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
