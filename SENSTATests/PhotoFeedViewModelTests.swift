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

  private func makePost() -> PhotoPost {
    PhotoPost(
      id: 101,
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
      throw PhotoFeedServiceError.networkUnavailable
    }
    return self.page
  }
}
