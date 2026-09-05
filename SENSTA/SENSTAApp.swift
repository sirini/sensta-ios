import Foundation
import SwiftUI

@main
struct SENSTAApp: App {
  private let photoFeedService: any PhotoFeedServing
  private let photoPostDetailService: any PhotoPostDetailServing

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-test-viewer") {
        photoFeedService = PaginationUITestService()
        photoPostDetailService = PhotoViewerUITestService()
        return
      }
      if ProcessInfo.processInfo.arguments.contains("--ui-test-pagination") {
        photoFeedService = PaginationUITestService()
        photoPostDetailService = UnavailablePhotoPostDetailService()
        return
      }
    #endif
    if let configuration = try? AppConfiguration.load(
      from: Bundle.main.infoDictionary ?? [:]
    ) {
      photoFeedService = PhotoFeedService(apiBaseURL: configuration.apiBaseURL)
      photoPostDetailService = PhotoPostDetailService(apiBaseURL: configuration.apiBaseURL)
    } else {
      photoFeedService = UnavailablePhotoFeedService()
      photoPostDetailService = UnavailablePhotoPostDetailService()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(service: photoFeedService, detailService: photoPostDetailService)
        #if DEBUG
          .preferredColorScheme(
            ProcessInfo.processInfo.arguments.contains("--ui-test-dark")
              ? .dark : ProcessInfo.processInfo.arguments.contains("--ui-test-light") ? .light : nil
          )
          .transformEnvironment(\.dynamicTypeSize) { size in
            if ProcessInfo.processInfo.arguments.contains("--ui-test-large-text") {
              size = .accessibility3
            }
          }
        #endif
    }
  }
}

#if DEBUG
  // 운영 데이터에 의존하지 않고 페이지 경계와 재시도 UI를 검증하는 전용 시나리오다.
  private actor PaginationUITestService: PhotoFeedServing {
    private var failedSecondPage = false
    func recentTags(boardID: Int) async throws -> [PhotoPostTag] {
      [PhotoPostTag(id: 10, name: "풍경"), PhotoPostTag(id: 11, name: "빛")]
    }

    func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws
      -> PhotoFeedPage
    {
      if keyword == "empty" { return PhotoFeedPage(totalPostCount: 0, posts: []) }
      let result = try await fetchPage(1)
      return PhotoFeedPage(totalPostCount: result.posts.count, posts: result.posts, boardID: 2)
    }

    func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
      if page == 2 && !failedSecondPage {
        failedSecondPage = true
        throw NuboAPIError.networkUnavailable
      }
      let ids = page == 1 ? Array(1...4) : page == 2 ? Array(5...6) : []
      return PhotoFeedPage(
        totalPostCount: 6,
        posts: ids.map { id in
          PhotoPost(
            id: id, title: "테스트 사진 \(id)", content: "", submitted: .now,
            viewCount: 0, coverURL: nil, commentCount: 0, likeCount: 0, isLiked: false,
            writer: PhotoPostWriter(id: 1, name: "테스트 사진가", profileURL: nil, badgeKeys: [])
          )
        },
        hasMorePages: page == 1, boardID: 2
      )
    }
  }
#endif

#if DEBUG
  private actor PhotoViewerUITestService: PhotoPostDetailServing {
    private var commentAttempts = 0

    private var photographerAttempts = 0
    func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
      photographerAttempts += 1
      if photographerAttempts == 1 { throw NuboAPIError.networkUnavailable }
      let post = try await fetchPost(id: 1).post
      return PhotographerProfile(
        writer: post.writer, signature: "빛과 여백, 일상 속 작은 순간을 기록합니다.", posts: [post],
        unavailableCount: 0,
        badges: [
          BoardBadgeDTO(
            key: "sensta-app", name: "SENSTA 앱 포토그래퍼", description: "SENSTA 앱으로 사진을 공유한 사용자입니다.",
            iconKey: "aperture", earnedAt: 1_788_410_731_496),
          BoardBadgeDTO(
            key: "first-post", name: "첫 발자국", description: "첫 게시글을 작성했습니다.",
            iconKey: "notebook-pen", earnedAt: 1_788_410_731_496),
        ], summary: PhotographerSummary(postCount: 24, photoCount: 58, likeCount: 132))
    }
    func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
      commentAttempts += 1
      if commentAttempts == 1 { throw NuboAPIError.networkUnavailable }
      return PhotoCommentsPage(
        comments: [
          PhotoComment(
            id: page, replyID: 1, writer: "사진가", content: "여백이 아름다운 사진입니다. \(page)",
            submitted: .now, likeCount: 2)
        ], hasMore: page == 1)
    }
    func fetchPost(id: Int) async throws -> PhotoPostDetail {
      let post = PhotoPost(
        id: id, title: "빛과 여백", content: "사진의 전체 구도를 감상하세요.",
        submitted: .now, viewCount: 3, coverURL: nil, commentCount: 0, likeCount: 1,
        isLiked: false, writer: PhotoPostWriter(id: 1, name: "사진가", profileURL: nil, badgeKeys: []))
      let exif = PhotoExif(
        make: "Panasonic", model: "DC-G100", aperture: 400, iso: 250, focalLength: 40,
        exposure: 16666, width: 900, height: 600, date: nil)
      return PhotoPostDetail(
        post: post,
        images: [1, 2].map {
          PhotoPostImage(
            id: $0, largeURL: nil, smallURL: nil,
            description: "나무 사이로 스며드는 빛과 차분한 여백이 어우러진 풍경입니다. 사진 \($0)", exif: exif)
        },
        tags: [], attachments: [], previousPostID: nil, nextPostID: nil, shareURL: nil, boardID: 2)
    }
  }
#endif
