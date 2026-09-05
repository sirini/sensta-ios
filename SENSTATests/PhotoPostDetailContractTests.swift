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

  @Test
  func photographerRequestsUseExactUIDWithoutAuthentication() throws {
    let base = try #require(URL(string: "https://sensta.me/goapi/"))
    for latest in [false, true] {
      let request = try PhotographerEndpoint.request(baseURL: base, userID: 42, latest: latest)
      let url = try #require(request.url)
      let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
      #expect(query.path == (latest ? "/goapi/board/user/latest" : "/goapi/auth/user/info"))
      #expect(query.queryItems?.first { $0.name == "targetUserUid" }?.value == "42")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      #expect(request.httpMethod == "GET")
    }
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotographerEndpoint.request(baseURL: base, userID: 0)
    }
  }

  @Test
  func photographerRejectsMismatchedAndBlockedProfiles() throws {
    let data = Data(
      #"{"success":true,"code":0,"error":"","result":{"uid":42,"name":"사진가","profile":"","signature":"소개","blocked":false}}"#
        .utf8)
    let info = try JSONDecoder().decode(PhotographerInfoDTO.self, from: data)
    #expect(try info.checked(userID: 42).name == "사진가")
    #expect(throws: NuboAPIError.invalidResponse) { try info.checked(userID: 43) }
    let blockedData = Data(
      String(decoding: data, as: UTF8.self).replacingOccurrences(of: "false", with: "true").utf8)
    let blocked = try JSONDecoder().decode(PhotographerInfoDTO.self, from: blockedData)
    #expect(throws: NuboAPIError.invalidResponse) { try blocked.checked(userID: 42) }
  }

  @Test
  func photographerLatestFiltersOtherBoardsInvalidIDsAndDuplicates() throws {
    let data = Data(
      #"{"success":true,"code":0,"error":"","result":{"posts":[{"postUid":101,"board":{"id":"photo"}},{"postUid":102,"board":{"id":"free"}},{"postUid":101,"board":{"id":"photo"}},{"postUid":0,"board":{"id":"photo"}},{"postUid":99,"board":{"id":"photo"}}]}}"#
        .utf8)
    #expect(
      try JSONDecoder().decode(PhotographerLatestDTO.self, from: data).photoIDs() == [101, 99])
    let failure = Data(#"{"success":false,"code":3,"error":"denied","result":null}"#.utf8)
    let response = try JSONDecoder().decode(PhotographerLatestDTO.self, from: failure)
    #expect(throws: NuboAPIError.server(code: 3, message: "denied")) { try response.photoIDs() }
  }

  @Test
  func publicSummaryRequestAndUnavailableResponse() throws {
    let base = try #require(URL(string: "https://sensta.me/goapi/"))
    let request = try PhotographerEndpoint.summaryRequest(baseURL: base, userID: 42)
    #expect(
      request.url?.absoluteString
        == "https://sensta.me/goapi/board/user/summary?id=photo&targetUserUid=42")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    for json in [
      #"{"success":true,"code":0,"error":"","result":null}"#,
      #"{"success":true,"code":0,"error":"","result":{"postCount":-1,"photoCount":0,"likeCount":0}}"#,
    ] {
      let dto = try JSONDecoder().decode(PhotographerSummaryDTO.self, from: Data(json.utf8))
      #expect(throws: NuboAPIError.malformedResponse) { try dto.checked() }
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

struct PhotographerServiceTests {
  @Test
  func summaryFailureDoesNotHideProfileAndWorks() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PhotographerURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let base = try #require(URL(string: "https://summary-unavailable.test/goapi/"))
    let profile = try await PhotoPostDetailService(apiBaseURL: base, session: session)
      .fetchPhotographer(id: 42)
    #expect(profile.writer.id == 42)
    #expect(profile.posts.map(\.id) == [101])
    #expect(profile.summary == nil)
  }

  @Test
  func onlyDisplaysValidatedPostIdentityAndReportsUnavailableWorks() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PhotographerURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let base = try #require(URL(string: "https://example.test/goapi/"))
    let profile = try await PhotoPostDetailService(apiBaseURL: base, session: session)
      .fetchPhotographer(id: 42)
    #expect(profile.writer.id == 42)
    #expect(profile.posts.map(\.id) == [101])
    #expect(profile.unavailableCount == 1)
    #expect(profile.summary?.postCount == 24)
    #expect(profile.summary?.photoCount == 58)
    #expect(profile.summary?.likeCount == 132)
  }
}

private final class PhotographerURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let url = try #require(request.url)
      let data: Data
      if url.path.hasSuffix("auth/user/info") {
        data = Data(
          #"{"success":true,"code":0,"error":"","result":{"uid":42,"name":"사진가","profile":"","signature":"소개","blocked":false}}"#
            .utf8)
      } else if url.path.hasSuffix("board/user/summary") {
        data = Data(
          #"{"success":true,"code":0,"error":"","result":{"postCount":24,"photoCount":58,"likeCount":132}}"#
            .utf8)
      } else if url.path.hasSuffix("board/user/latest") {
        data = Data(
          #"{"success":true,"code":0,"error":"","result":{"posts":[{"postUid":101,"board":{"id":"photo"}},{"postUid":102,"board":{"id":"photo"}}]}}"#
            .utf8)
      } else {
        let fixture = try #require(
          Bundle(for: PhotoDetailFixtureBundleMarker.self).url(
            forResource: "board-view-photo", withExtension: "json"))
        data = try Data(contentsOf: fixture)
      }
      let response = try #require(
        HTTPURLResponse(
          url: url,
          statusCode: url.host == "summary-unavailable.test"
            && url.path.hasSuffix("board/user/summary") ? 404 : 200, httpVersion: nil,
          headerFields: nil))
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
