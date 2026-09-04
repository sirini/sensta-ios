import Foundation

struct AppConfiguration: Equatable, Sendable {
  enum ConfigurationError: Error, Equatable {
    case missingAPIBaseURL
    case invalidAPIBaseURL(String)
  }

  let apiBaseURL: URL

  static func load(from infoDictionary: [String: Any]) throws -> AppConfiguration {
    guard let value = infoDictionary["APIBaseURL"] as? String, !value.isEmpty else {
      throw ConfigurationError.missingAPIBaseURL
    }
    guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
      throw ConfigurationError.invalidAPIBaseURL(value)
    }
    return AppConfiguration(apiBaseURL: url)
  }
}
