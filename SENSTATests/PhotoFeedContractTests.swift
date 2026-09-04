import Foundation
import Testing

@testable import SENSTA

struct PhotoFeedContractTests {
  @Test
  func decodesBoardListFixtureAndMapsMediaURLs() throws {
    let data = try fixtureData(named: "board-list-photo")
    let response = try JSONDecoder().decode(BoardListResponseDTO.self, from: data)
    let page = try response.makeFeedPage(
      apiBaseURL: #require(URL(string: "https://sensta.me/goapi/"))
    )

    #expect(response.result?.config.id == "photo")
    #expect(response.result?.config.rowCount == 32)
    #expect(page.totalPostCount == 2)
    #expect(page.posts.count == 1)
    #expect(page.posts[0].id == 101)
    #expect(page.posts[0].writer.name == "사진가")
    #expect(page.posts[0].writer.badgeKeys == ["sensta-app"])
    #expect(
      page.posts[0].coverURL?.absoluteString
        == "https://sensta.me/upload/thumbnails/2026/09/04/fsample.webp"
    )
    #expect(
      page.posts[0].writer.profileURL?.absoluteString
        == "https://sensta.me/upload/profile/sample.webp"
    )
  }

  @Test
  func buildsAnonymousPhotoListRequest() throws {
    let request = try PhotoFeedEndpoint.makeRequest(
      apiBaseURL: #require(URL(string: "https://sensta.me/goapi/")),
      page: 3
    )
    let requestURL = try #require(request.url)
    let components = try #require(
      URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
    )
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )

    #expect(request.httpMethod == "GET")
    #expect(components.path == "/goapi/board/list")
    #expect(query == ["id": "photo", "page": "3", "option": "0", "keyword": ""])
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
  }

  @Test
  func rejectsApplicationErrorEnvelope() throws {
    let data = Data(
      #"{"success":false,"error":"invalid board","code":3,"result":null}"#.utf8
    )
    let response = try JSONDecoder().decode(BoardListResponseDTO.self, from: data)

    #expect(throws: PhotoFeedServiceError.server(code: 3, message: "invalid board")) {
      try response.makeFeedPage(
        apiBaseURL: #require(URL(string: "https://sensta.me/goapi/"))
      )
    }
  }

  private func fixtureData(named name: String) throws -> Data {
    let url = try #require(
      Bundle(for: FixtureBundleMarker.self).url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
  }
}

private final class FixtureBundleMarker {}
