import Foundation

protocol PhotoPostDetailServing: Sendable {
  func fetchPost(id: Int) async throws -> PhotoPostDetail
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
