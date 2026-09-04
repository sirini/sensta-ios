import Foundation
import Testing

@testable import SENSTA

struct PhotoPostDetailContractTests {
  @Test
  func decodesBoardViewFixtureAndMapsDetail() throws {
    let data = try fixtureData(named: "board-view-photo")
    let response = try JSONDecoder().decode(BoardViewResponseDTO.self, from: data)
    let detail = try response.makePhotoPostDetail(
      apiBaseURL: #require(URL(string: "https://sensta.me/goapi/"))
    )

    #expect(response.result?.config.id == "photo")
    #expect(detail.post.id == 101)
    #expect(detail.images.count == 2)
    #expect(detail.images[0].id == 501)
    #expect(
      detail.images[0].largeURL?.absoluteString
        == "https://sensta.me/upload/thumbnails/2026/09/04/lsample.webp"
    )
    #expect(detail.images[0].exif.aperture == 180)
    #expect(detail.images[0].description == "노을빛을 받은 나무와 산책로가 보입니다.")
    #expect(detail.tags.map(\.name) == ["가을", "산책"])
    #expect(detail.attachments.first?.name == "원본사진.heic")
    #expect(detail.previousPostID == nil)
    #expect(detail.nextPostID == 102)
    #expect(detail.shareURL?.absoluteString == "https://sensta.me/board/photo/101")
  }

  @Test
  func buildsAnonymousPhotoDetailRequest() throws {
    let request = try PhotoPostDetailEndpoint.makeRequest(
      apiBaseURL: #require(URL(string: "https://sensta.me/goapi/")),
      postID: 101
    )
    let requestURL = try #require(request.url)
    let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )

    #expect(request.httpMethod == "GET")
    #expect(components.path == "/goapi/board/view")
    #expect(
      query == ["id": "photo", "postUid": "101", "needUpdateHit": "0", "latestLimit": "5"]
    )
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
  }

  @Test
  func rejectsDetailApplicationErrorEnvelope() throws {
    let data = Data(
      #"{"success":false,"error":"invalid post","code":4,"result":null}"#.utf8
    )
    let response = try JSONDecoder().decode(BoardViewResponseDTO.self, from: data)

    #expect(throws: NuboAPIError.server(code: 4, message: "invalid post")) {
      try response.makePhotoPostDetail(
        apiBaseURL: #require(URL(string: "https://sensta.me/goapi/"))
      )
    }
  }

  private func fixtureData(named name: String) throws -> Data {
    let url = try #require(
      Bundle(for: PhotoDetailFixtureBundleMarker.self).url(
        forResource: name,
        withExtension: "json"
      )
    )
    return try Data(contentsOf: url)
  }
}

private final class PhotoDetailFixtureBundleMarker {}
