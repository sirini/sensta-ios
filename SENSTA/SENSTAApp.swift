import Foundation
import SwiftUI

@main
struct SENSTAApp: App {
  private let photoFeedService: any PhotoFeedServing

  init() {
    if let configuration = try? AppConfiguration.load(
      from: Bundle.main.infoDictionary ?? [:]
    ) {
      photoFeedService = PhotoFeedService(apiBaseURL: configuration.apiBaseURL)
    } else {
      photoFeedService = UnavailablePhotoFeedService()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(service: photoFeedService)
    }
  }
}
