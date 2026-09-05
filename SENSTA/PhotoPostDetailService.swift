import Foundation

protocol PhotoPostDetailServing: PhotoCommentsServing {
  func fetchPhotographer(id: Int) async throws -> PhotographerProfile
  func fetchPost(id: Int) async throws -> PhotoPostDetail
}

extension PhotoPostDetailServing {
  func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
    throw NuboAPIError.configuration
  }
  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
    throw NuboAPIError.configuration
  }
}

enum PhotoPostDetailEndpoint {
  static func makeRequest(apiBaseURL: URL, postID: Int) throws -> URLRequest {
    guard postID > 0 else {
      throw NuboAPIError.invalidRequest
    }

    let endpointURL = apiBaseURL.appending(path: "board/view")
    guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
      throw NuboAPIError.invalidRequest
    }
    components.queryItems = [
      URLQueryItem(name: "id", value: "photo"),
      URLQueryItem(name: "postUid", value: String(postID)),
      URLQueryItem(name: "needUpdateHit", value: "0"),
      URLQueryItem(name: "latestLimit", value: "5"),
    ]
    guard let url = components.url else {
      throw NuboAPIError.invalidRequest
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct PhotoPostDetailService: PhotoPostDetailServing {
  private let client: NuboAPIClient

  init(apiBaseURL: URL, session: URLSession = .shared) {
    client = NuboAPIClient(apiBaseURL: apiBaseURL, session: session)
  }

  func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
    let infoData = try await client.data(
      for: PhotographerEndpoint.request(baseURL: client.apiBaseURL, userID: id))
    let info = try JSONDecoder().decode(PhotographerInfoDTO.self, from: infoData).checked(
      userID: id)
    let latestData = try await client.data(
      for: PhotographerEndpoint.request(baseURL: client.apiBaseURL, userID: id, latest: true))
    let ids = try JSONDecoder().decode(PhotographerLatestDTO.self, from: latestData).photoIDs()
    var posts: [PhotoPost] = []
    var unavailable = 0
    // 최근 활동 응답의 제목을 바로 노출하지 않고 상세 API의 공개 접근 검사를 거친다.
    for start in stride(from: 0, to: ids.count, by: 3) {
      try Task.checkCancellation()
      let batch = Array(ids[start..<min(start + 3, ids.count)])
      let results = try await withThrowingTaskGroup(of: (Int, PhotoPost?).self) { group in
        for (index, postID) in batch.enumerated() {
          group.addTask {
            do {
              let detail = try await fetchPost(id: postID)
              guard detail.post.id == postID, detail.post.writer.id == id else {
                return (index, nil)
              }
              return (index, detail.post)
            } catch is CancellationError { throw CancellationError() } catch { return (index, nil) }
          }
        }
        var results: [(Int, PhotoPost?)] = []
        for try await result in group { results.append(result) }
        return results.sorted { $0.0 < $1.0 }
      }
      for (_, post) in results {
        if let post { posts.append(post) } else { unavailable += 1 }
      }
    }
    var summary: PhotographerSummary?
    do {
      let data = try await client.data(
        for: PhotographerEndpoint.summaryRequest(baseURL: client.apiBaseURL, userID: id))
      summary = try JSONDecoder().decode(PhotographerSummaryDTO.self, from: data).checked()
    } catch is CancellationError { throw CancellationError() } catch { summary = nil }
    var badgeKeys = Set<String>()
    let badges = (info.badges ?? []).filter { !$0.key.isEmpty && badgeKeys.insert($0.key).inserted }
    return PhotographerProfile(
      writer: PhotoPostWriter(
        id: id, name: info.name,
        profileURL: MediaURLResolver.url(for: info.profile, apiBaseURL: client.apiBaseURL),
        badgeKeys: info.badges?.map(\.key) ?? []), signature: info.signature, posts: posts,
      unavailableCount: unavailable, badges: badges, summary: summary)
  }

  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
    let request = try PhotoCommentsEndpoint.makeRequest(
      apiBaseURL: client.apiBaseURL, boardID: boardID, postID: postID, page: page)
    let data = try await client.data(for: request)
    let envelope: PhotoCommentsResponseDTO
    do { envelope = try JSONDecoder().decode(PhotoCommentsResponseDTO.self, from: data) } catch {
      throw NuboAPIError.malformedResponse
    }
    return try envelope.makePage(boardID: boardID, postID: postID, page: page)
  }

  func fetchPost(id: Int) async throws -> PhotoPostDetail {
    let request = try PhotoPostDetailEndpoint.makeRequest(
      apiBaseURL: client.apiBaseURL,
      postID: id
    )
    let data = try await client.data(for: request)

    let envelope: BoardViewResponseDTO
    do {
      envelope = try JSONDecoder().decode(BoardViewResponseDTO.self, from: data)
    } catch {
      throw NuboAPIError.malformedResponse
    }
    return try envelope.makePhotoPostDetail(apiBaseURL: client.apiBaseURL)
  }
}

struct UnavailablePhotoPostDetailService: PhotoPostDetailServing {
  func fetchPost(id: Int) async throws -> PhotoPostDetail {
    throw NuboAPIError.configuration
  }
}
