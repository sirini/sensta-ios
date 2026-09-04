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
    if showsLoadingState {
      state = .loading
    }
    defer { requestInFlight = false }

    do {
      let page = try await service.fetchPage(1)
      state = page.posts.isEmpty ? .empty : .loaded(page.posts)
    } catch is CancellationError {
      state = previousState
    } catch {
      state = .failed(Self.userMessage(for: error))
    }
  }

  private static func userMessage(for error: Error) -> String {
    if let error = error as? PhotoFeedServiceError,
      let description = error.errorDescription
    {
      return description
    }
    return "사진을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
  }
}
