import Foundation

struct PhotoFeedPage: Equatable, Sendable {
  let totalPostCount: Int
  let posts: [PhotoPost]
}

struct PhotoPost: Identifiable, Equatable, Sendable {
  let id: Int
  let title: String
  let content: String
  let submitted: Date
  let viewCount: Int
  let coverURL: URL?
  let commentCount: Int
  let likeCount: Int
  let isLiked: Bool
  let writer: PhotoPostWriter
}

struct PhotoPostWriter: Equatable, Sendable {
  let id: Int
  let name: String
  let profileURL: URL?
  let badgeKeys: [String]
}

struct BoardListResponseDTO: Decodable, Sendable {
  let success: Bool
  let error: String
  let code: Int
  let result: BoardListResultDTO?

  func makeFeedPage(apiBaseURL: URL) throws -> PhotoFeedPage {
    guard success, code == 0 else {
      throw PhotoFeedServiceError.server(code: code, message: error)
    }
    guard let result else {
      throw PhotoFeedServiceError.malformedResponse
    }

    let blockedWriterIDs = Set(result.blackList)
    let posts = result.posts
      .filter { !blockedWriterIDs.contains($0.writer.uid) }
      .map { $0.makePhotoPost(apiBaseURL: apiBaseURL) }

    return PhotoFeedPage(totalPostCount: result.totalPostCount, posts: posts)
  }
}

struct BoardListResultDTO: Decodable, Sendable {
  let totalPostCount: Int
  let config: BoardConfigDTO
  let notices: [BoardPostDTO]
  let posts: [BoardPostDTO]
  let blackList: [Int]
  let isAdmin: Bool
}

struct BoardConfigDTO: Decodable, Sendable {
  let uid: Int
  let id: String
  let name: String
  let rowCount: Int
}

struct BoardPostDTO: Decodable, Sendable {
  let uid: Int
  let title: String
  let content: String
  let submitted: Int64
  let modified: Int64
  let hit: Int
  let status: Int
  let category: BoardCategoryDTO
  let cover: String
  let comment: Int
  let like: Int
  let liked: Bool
  let writer: BoardWriterDTO

  func makePhotoPost(apiBaseURL: URL) -> PhotoPost {
    PhotoPost(
      id: uid,
      title: title,
      content: content,
      submitted: Date(timeIntervalSince1970: Double(submitted) / 1_000),
      viewCount: hit,
      coverURL: Self.mediaURL(for: Self.previewImagePath(for: cover), apiBaseURL: apiBaseURL),
      commentCount: comment,
      likeCount: like,
      isLiked: liked,
      writer: PhotoPostWriter(
        id: writer.uid,
        name: writer.name,
        profileURL: Self.mediaURL(for: writer.profile, apiBaseURL: apiBaseURL),
        badgeKeys: writer.badges?.map(\.key) ?? []
      )
    )
  }

  private static func previewImagePath(for path: String) -> String {
    let pattern = #"(/upload/thumbnails/(?:[^/]+/)*)t([^/?]+)(?=$|[?#])"#
    return path.replacingOccurrences(
      of: pattern,
      with: "$1f$2",
      options: .regularExpression
    )
  }

  private static func mediaURL(for path: String, apiBaseURL: URL) -> URL? {
    guard !path.isEmpty,
      let url = URL(string: path, relativeTo: apiBaseURL)?.absoluteURL,
      url.scheme == "https"
    else {
      return nil
    }
    return url
  }
}

struct BoardCategoryDTO: Decodable, Sendable {
  let uid: Int
  let name: String
}

struct BoardWriterDTO: Decodable, Sendable {
  let uid: Int
  let name: String
  let profile: String
  let signature: String
  let badges: [BoardBadgeDTO]?
}

struct BoardBadgeDTO: Decodable, Sendable {
  let key: String
  let name: String
  let description: String
  let iconKey: String
  let earnedAt: Int64
}
