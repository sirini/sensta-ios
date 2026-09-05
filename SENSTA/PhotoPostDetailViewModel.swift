import Observation

@MainActor
@Observable
final class PhotoPostDetailViewModel {
  enum State: Equatable {
    case idle
    case loading
    case loaded(PhotoPostDetail)
    case failed(String)
  }

  private let postID: Int
  private let service: any PhotoPostDetailServing
  private var requestInFlight = false
  private(set) var state: State = .idle

  init(postID: Int, service: any PhotoPostDetailServing) {
    self.postID = postID
    self.service = service
  }

  func loadIfNeeded() async {
    guard state == .idle else { return }
    await load()
  }

  func retry() async {
    await load()
  }

  private func load() async {
    guard !requestInFlight else { return }
    let previousState = state
    requestInFlight = true
    state = .loading
    defer { requestInFlight = false }

    do {
      let detail = try await service.fetchPost(id: postID)
      try Task.checkCancellation()
      state = .loaded(detail)
    } catch is CancellationError {
      state = previousState
    } catch {
      state = .failed(Self.userMessage(for: error))
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
