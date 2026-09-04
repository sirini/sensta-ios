import Foundation
import Testing

@testable import SENSTA

struct AppConfigurationTests {
  @Test
  func loadsHTTPSAPIBaseURL() throws {
    let configuration = try AppConfiguration.load(from: [
      "APIBaseURL": "https://sensta.me/goapi/"
    ])

    #expect(configuration.apiBaseURL == URL(string: "https://sensta.me/goapi/"))
  }

  @Test
  func rejectsMissingAPIBaseURL() {
    #expect(throws: AppConfiguration.ConfigurationError.missingAPIBaseURL) {
      try AppConfiguration.load(from: [:])
    }
  }

  @Test
  func rejectsNonHTTPSAPIBaseURL() {
    #expect(throws: AppConfiguration.ConfigurationError.invalidAPIBaseURL("http://localhost")) {
      try AppConfiguration.load(from: ["APIBaseURL": "http://localhost"])
    }
  }
}
