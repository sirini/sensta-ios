import Foundation

protocol PhotoFeedServing: Sendable {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage
  func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws -> PhotoFeedPage
  func recentTags(boardID: Int) async throws -> [PhotoPostTag]
}

extension PhotoFeedServing {
  func recentTags(boardID: Int) async throws -> [PhotoPostTag] { throw NuboAPIError.configuration }
  func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws -> PhotoFeedPage
  {
    throw NuboAPIError.configuration
  }
}

enum NuboAPIError: Error, Equatable, LocalizedError, Sendable {
  case invalidRequest
  case invalidResponse
  case httpStatus(Int)
  case server(code: Int, message: String)
  case malformedResponse
  case networkUnavailable
  case timedOut
  case networkFailure
  case configuration

  var errorDescription: String? {
    switch self {
    case .networkUnavailable:
      "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
    case .timedOut:
      "서버 응답이 늦어지고 있어요. 잠시 뒤 다시 시도해 주세요."
    case .server, .httpStatus, .invalidResponse, .malformedResponse, .networkFailure:
      "잠시 뒤 다시 시도해 주세요."
    case .invalidRequest, .configuration:
      "앱 설정을 확인하지 못했어요."
    }
  }
}

enum PhotoFeedEndpoint {
  static func makeRequest(
    apiBaseURL: URL, page: Int, keyword: String = "", option: PhotoSearchOption = .title
  ) throws -> URLRequest {
    guard page > 0 else {
      throw NuboAPIError.invalidRequest
    }

    let endpointURL = apiBaseURL.appending(path: "board/list")
    guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
      throw NuboAPIError.invalidRequest
    }
    components.queryItems = [
      URLQueryItem(name: "id", value: "photo"),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "option", value: String(option.rawValue)),
      // GOAPI는 Query 값에 QueryUnescape를 한 번 더 적용하므로 검색어를 한 번 더 인코딩한다.
      URLQueryItem(
        name: "keyword", value: keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
      ),
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

struct NuboAPIClient: Sendable {
  let apiBaseURL: URL
  private let session: URLSession

  init(apiBaseURL: URL, session: URLSession = .shared) {
    self.apiBaseURL = apiBaseURL
    self.session = session
  }

  func data(for request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse

    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      switch error.code {
      case .cancelled:
        throw CancellationError()
      case .notConnectedToInternet, .networkConnectionLost:
        throw NuboAPIError.networkUnavailable
      case .timedOut:
        throw NuboAPIError.timedOut
      default:
        throw NuboAPIError.networkFailure
      }
    } catch {
      throw NuboAPIError.networkFailure
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NuboAPIError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw NuboAPIError.httpStatus(httpResponse.statusCode)
    }
    return data
  }
}

struct PhotoFeedService: PhotoFeedServing {
  private let client: NuboAPIClient

  init(apiBaseURL: URL, session: URLSession = .shared) {
    client = NuboAPIClient(apiBaseURL: apiBaseURL, session: session)
  }

  func recentTags(boardID: Int) async throws -> [PhotoPostTag] {
    let request = try PhotoRecentTagsEndpoint.makeRequest(
      apiBaseURL: client.apiBaseURL, boardID: boardID)
    let data = try await client.data(for: request)
    let response: PhotoRecentTagsResponseDTO
    do { response = try JSONDecoder().decode(PhotoRecentTagsResponseDTO.self, from: data) } catch {
      throw NuboAPIError.malformedResponse
    }
    return try response.makeTags()
  }

  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    try await search("", page: page, option: .title)
  }

  func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws -> PhotoFeedPage
  {
    let request = try PhotoFeedEndpoint.makeRequest(
      apiBaseURL: client.apiBaseURL, page: page, keyword: keyword, option: option)
    let data = try await client.data(for: request)

    let envelope: BoardListResponseDTO
    do {
      envelope = try JSONDecoder().decode(BoardListResponseDTO.self, from: data)
    } catch {
      throw NuboAPIError.malformedResponse
    }
    return try envelope.makeFeedPage(apiBaseURL: client.apiBaseURL, requestedPage: page)
  }
}

struct UnavailablePhotoFeedService: PhotoFeedServing {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    throw NuboAPIError.configuration
  }
}

enum PhotoRecentTagsEndpoint {
  static func makeRequest(apiBaseURL: URL, boardID: Int) throws -> URLRequest {
    guard boardID > 0,
      var components = URLComponents(
        url: apiBaseURL.appending(path: "board/tag/recent"),
        resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "boardUid", value: String(boardID)),
      URLQueryItem(name: "limit", value: "12"),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct PhotoRecentTagsResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: [BoardTagDTO]?

  func makeTags() throws -> [PhotoPostTag] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result else { throw NuboAPIError.malformedResponse }
    var seen = Set<Int>()
    return result.compactMap { tag in
      guard tag.uid > 0, !tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        seen.insert(tag.uid).inserted
      else { return nil }
      return PhotoPostTag(id: tag.uid, name: tag.name)
    }
  }
}
