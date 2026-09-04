import Foundation
import Testing

@testable import SENSTA

@MainActor
struct PhotoPostDetailViewModelTests {
  @Test
  func loadsDetail() async {
    let detail = makeDetail()
    let model = PhotoPostDetailViewModel(
      postID: detail.post.id,
      service: SuccessfulPhotoPostDetailService(detail: detail)
    )

    await model.loadIfNeeded()

    #expect(model.state == .loaded(detail))
  }

  @Test
  func presentsErrorAndRetries() async {
    let detail = makeDetail()
    let service = RetryPhotoPostDetailService(detail: detail)
    let model = PhotoPostDetailViewModel(postID: detail.post.id, service: service)

    await model.loadIfNeeded()
    guard case .failed(let message) = model.state else {
      Issue.record("첫 요청은 오류 상태여야 합니다.")
      return
    }
    #expect(message == "인터넷 연결을 확인한 뒤 다시 시도해 주세요.")

    await model.retry()

    #expect(model.state == .loaded(detail))
    #expect(await service.attemptCount == 2)
  }

  private func makeDetail() -> PhotoPostDetail {
    PhotoPostDetail(
      post: PhotoPost(
        id: 101,
        title: "테스트 사진",
        content: "본문",
        submitted: Date(timeIntervalSince1970: 1_788_500_000),
        viewCount: 3,
        coverURL: nil,
        commentCount: 1,
        likeCount: 2,
        isLiked: false,
        writer: PhotoPostWriter(id: 42, name: "사진가", profileURL: nil, badgeKeys: [])
      ),
      images: [],
      tags: [],
      attachments: [],
      previousPostID: nil,
      nextPostID: nil,
      shareURL: URL(string: "https://sensta.me/board/photo/101")
    )
  }
}

private struct SuccessfulPhotoPostDetailService: PhotoPostDetailServing {
  let detail: PhotoPostDetail

  func fetchPost(id: Int) async throws -> PhotoPostDetail { detail }
}

private actor RetryPhotoPostDetailService: PhotoPostDetailServing {
  let detail: PhotoPostDetail
  private(set) var attemptCount = 0

  init(detail: PhotoPostDetail) {
    self.detail = detail
  }

  func fetchPost(id: Int) async throws -> PhotoPostDetail {
    attemptCount += 1
    if attemptCount == 1 {
      throw NuboAPIError.networkUnavailable
    }
    return detail
  }
}
