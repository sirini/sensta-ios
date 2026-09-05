import Foundation

struct PhotoPostDetail: Equatable, Sendable {
  let post: PhotoPost
  let images: [PhotoPostImage]
  let tags: [PhotoPostTag]
  let attachments: [PhotoPostAttachment]
  let previousPostID: Int?
  let nextPostID: Int?
  let shareURL: URL?
  var boardID: Int? = nil
}

struct PhotoPostImage: Identifiable, Equatable, Sendable {
  let id: Int
  let largeURL: URL?
  let smallURL: URL?
  let description: String
  let exif: PhotoExif
}

struct PhotoExif: Equatable, Sendable {
  let make: String
  let model: String
  let aperture: Int?
  let iso: Int?
  let focalLength: Int?
  let exposure: Int?
  let width: Int?
  let height: Int?
  let date: Date?
}

struct PhotoPostTag: Identifiable, Equatable, Sendable {
  let id: Int
  let name: String
}

struct PhotoPostAttachment: Identifiable, Equatable, Sendable {
  let id: Int
  let name: String
  let size: Int64
}

struct BoardViewResponseDTO: Decodable, Sendable {
  let success: Bool
  let error: String
  let code: Int
  let result: BoardViewResultDTO?

  func makePhotoPostDetail(apiBaseURL: URL) throws -> PhotoPostDetail {
    guard success, code == 0 else {
      throw NuboAPIError.server(code: code, message: error)
    }
    guard let result else {
      throw NuboAPIError.malformedResponse
    }

    return PhotoPostDetail(
      post: result.post.makePhotoPost(apiBaseURL: apiBaseURL),
      images: result.images.map { $0.makePhotoPostImage(apiBaseURL: apiBaseURL) },
      tags: result.tags.map { PhotoPostTag(id: $0.uid, name: $0.name) },
      attachments: result.files.map {
        PhotoPostAttachment(id: $0.uid, name: $0.name, size: $0.size)
      },
      previousPostID: result.prevPostUid > 0 ? result.prevPostUid : nil,
      nextPostID: result.nextPostUid > 0 ? result.nextPostUid : nil,
      shareURL: MediaURLResolver.url(
        for: "/board/photo/\(result.post.uid)",
        apiBaseURL: apiBaseURL
      ),
      boardID: result.config.uid
    )
  }
}

struct BoardViewResultDTO: Decodable, Sendable {
  let config: BoardConfigDTO
  let post: BoardPostDTO
  let images: [BoardImageDTO]
  let files: [BoardAttachmentDTO]
  let tags: [BoardTagDTO]
  let prevPostUid: Int
  let nextPostUid: Int
  let writerPosts: [BoardWriterPostDTO]
  let writerComments: [BoardWriterCommentDTO]
  let isAdmin: Bool?
}

struct BoardImageDTO: Decodable, Sendable {
  let file: BoardImageFileDTO
  let thumbnail: BoardThumbnailDTO
  let exif: BoardExifDTO
  let description: String

  func makePhotoPostImage(apiBaseURL: URL) -> PhotoPostImage {
    PhotoPostImage(
      id: file.uid,
      largeURL: MediaURLResolver.url(for: thumbnail.large, apiBaseURL: apiBaseURL),
      smallURL: MediaURLResolver.url(for: thumbnail.small, apiBaseURL: apiBaseURL),
      description: description,
      exif: PhotoExif(
        make: exif.make,
        model: exif.model,
        aperture: exif.aperture.nonzero,
        iso: exif.iso.nonzero,
        focalLength: exif.focalLength.nonzero,
        exposure: exif.exposure.nonzero,
        width: exif.width.nonzero,
        height: exif.height.nonzero,
        date: exif.date > 0 ? Date(timeIntervalSince1970: Double(exif.date) / 1_000) : nil
      )
    )
  }
}

struct BoardImageFileDTO: Decodable, Sendable { let uid: Int }

struct BoardThumbnailDTO: Decodable, Sendable {
  let large: String
  let small: String
}

struct BoardExifDTO: Decodable, Sendable {
  let make: String
  let model: String
  let aperture: Int
  let iso: Int
  let focalLength: Int
  let exposure: Int
  let width: Int
  let height: Int
  let date: Int64
}

struct BoardAttachmentDTO: Decodable, Sendable {
  let uid: Int
  let name: String
  let size: Int64
}

struct BoardTagDTO: Decodable, Sendable {
  let uid: Int
  let name: String
}

struct BoardWriterPostDTO: Decodable, Sendable {
  let board: BoardSummaryDTO
  let postUid: Int
  let like: Int
  let submitted: Int64
  let comment: Int
  let title: String
}

struct BoardWriterCommentDTO: Decodable, Sendable {
  let board: BoardSummaryDTO
  let postUid: Int
  let like: Int
  let submitted: Int64
  let content: String
}

struct BoardSummaryDTO: Decodable, Sendable {
  let id: String
  let type: Int
  let name: String
}

extension Int {
  fileprivate var nonzero: Int? { self == 0 ? nil : self }
}
