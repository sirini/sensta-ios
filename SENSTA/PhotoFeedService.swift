import Foundation

protocol PhotoFeedServing: Sendable {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage
}

enum PhotoFeedServiceError: Error, Equatable, LocalizedError, Sendable {
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
  static func makeRequest(apiBaseURL: URL, page: Int) throws -> URLRequest {
    guard page > 0 else {
      throw PhotoFeedServiceError.invalidRequest
    }

    let endpointURL = apiBaseURL.appending(path: "board/list")
    guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
      throw PhotoFeedServiceError.invalidRequest
    }
    components.queryItems = [
      URLQueryItem(name: "id", value: "photo"),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "option", value: "0"),
      URLQueryItem(name: "keyword", value: ""),
    ]
    guard let url = components.url else {
      throw PhotoFeedServiceError.invalidRequest
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct PhotoFeedService: PhotoFeedServing {
  private let apiBaseURL: URL
  private let session: URLSession

  init(apiBaseURL: URL, session: URLSession = .shared) {
    self.apiBaseURL = apiBaseURL
    self.session = session
  }

  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    let request = try PhotoFeedEndpoint.makeRequest(apiBaseURL: apiBaseURL, page: page)
    let data: Data
    let response: URLResponse

    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost:
        throw PhotoFeedServiceError.networkUnavailable
      case .timedOut:
        throw PhotoFeedServiceError.timedOut
      default:
        throw PhotoFeedServiceError.networkFailure
      }
    } catch {
      throw PhotoFeedServiceError.networkFailure
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw PhotoFeedServiceError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw PhotoFeedServiceError.httpStatus(httpResponse.statusCode)
    }

    let envelope: BoardListResponseDTO
    do {
      envelope = try JSONDecoder().decode(BoardListResponseDTO.self, from: data)
    } catch {
      throw PhotoFeedServiceError.malformedResponse
    }
    return try envelope.makeFeedPage(apiBaseURL: apiBaseURL)
  }
}

struct UnavailablePhotoFeedService: PhotoFeedServing {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    throw PhotoFeedServiceError.configuration
  }
}
