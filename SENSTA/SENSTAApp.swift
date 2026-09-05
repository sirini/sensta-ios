import Foundation
import SwiftUI

@main
struct SENSTAApp: App {
  private let photoFeedService: any PhotoFeedServing
  private let photoPostDetailService: any PhotoPostDetailServing

  init() {
    #if DEBUG
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
    }
  }
}

#if DEBUG
  // 운영 데이터에 의존하지 않고 페이지 경계와 재시도 UI를 검증하는 전용 시나리오다.
  private actor PaginationUITestService: PhotoFeedServing {
    private var failedSecondPage = false
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
        hasMorePages: page == 1
      )
    }
  }
#endif
