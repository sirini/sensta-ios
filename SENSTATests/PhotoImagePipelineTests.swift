import Foundation
import Testing
import UIKit

@testable import SENSTA

@Suite(.serialized)
@MainActor
struct PhotoImagePipelineTests {
  @Test
  func downsamplesToRequestedPixelSize() throws {
    let data = try makeJPEGData(width: 1_200, height: 1_800)

    let decoded = try ImageDownsampler.decode(
      data: data,
      maxPixelSize: 300,
      displayScale: 1
    )
    let cgImage = try #require(decoded.image.cgImage)

    #expect(max(cgImage.width, cgImage.height) == 300)
    #expect(min(cgImage.width, cgImage.height) == 200)
    #expect(decoded.memoryCost == cgImage.bytesPerRow * cgImage.height)
  }

  @Test
  func keepsEnoughLandscapePixelsForPortraitFill() throws {
    let data = try makeJPEGData(width: 1_800, height: 900)

    let decoded = try ImageDownsampler.decodeToFill(
      data: data,
      targetPixelSize: CGSize(width: 200, height: 300),
      displayScale: 1
    )
    let cgImage = try #require(decoded.image.cgImage)

    #expect(cgImage.width == 600)
    #expect(cgImage.height == 300)
  }

  @Test
  func reusesDisplaySizedImageFromMemoryCache() async throws {
    let data = try makeJPEGData(width: 600, height: 900)
    ImageURLProtocolStub.prepare(responseData: data)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageURLProtocolStub.self]
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    let pipeline = PhotoImagePipeline(
      session: session,
      responseCache: nil,
      decodedMemoryCapacity: 8 * 1_024 * 1_024
    )
    let url = try #require(URL(string: "https://example.test/photo.jpg"))

    let first = try await pipeline.image(
      for: url,
      targetSize: CGSize(width: 100, height: 150),
      displayScale: 2
    )
    let second = try await pipeline.image(
      for: url,
      targetSize: CGSize(width: 100, height: 150),
      displayScale: 2
    )

    #expect(first.image === second.image)
    #expect(ImageURLProtocolStub.receivedRequestCount == 1)
    session.invalidateAndCancel()
  }

  @Test
  func coalescesSimultaneousRequestsForSameDisplaySize() async throws {
    let data = try makeJPEGData(width: 600, height: 900)
    ImageURLProtocolStub.prepare(responseData: data, responseDelay: 0.05)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageURLProtocolStub.self]
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    let pipeline = PhotoImagePipeline(
      session: session,
      responseCache: nil,
      decodedMemoryCapacity: 8 * 1_024 * 1_024
    )
    let url = try #require(URL(string: "https://example.test/same-photo.jpg"))

    async let first = pipeline.image(
      for: url,
      targetSize: CGSize(width: 100, height: 150),
      displayScale: 2
    )
    async let second = pipeline.image(
      for: url,
      targetSize: CGSize(width: 100, height: 150),
      displayScale: 2
    )
    let images = try await [first, second]

    #expect(images[0].image === images[1].image)
    #expect(ImageURLProtocolStub.receivedRequestCount == 1)
    session.invalidateAndCancel()
  }

  private func makeJPEGData(width: Int, height: Int) throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: width, height: height),
      format: format
    ).image { context in
      UIColor.systemIndigo.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return try #require(image.jpegData(compressionQuality: 0.9))
  }
}

private final class ImageURLProtocolStub: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var responseData = Data()
  nonisolated(unsafe) private static var requestCount = 0
  nonisolated(unsafe) private static var responseDelay: TimeInterval = 0

  static var receivedRequestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestCount
  }

  static func prepare(responseData: Data, responseDelay: TimeInterval = 0) {
    lock.lock()
    self.responseData = responseData
    self.responseDelay = responseDelay
    requestCount = 0
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.requestCount += 1
    let data = Self.responseData
    let delay = Self.responseDelay
    Self.lock.unlock()

    if delay > 0 {
      Thread.sleep(forTimeInterval: delay)
    }

    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "image/jpeg"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
