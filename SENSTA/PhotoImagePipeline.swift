import Foundation
import ImageIO
import SwiftUI
import UIKit

enum PhotoImagePipelineError: Error, Sendable {
  case invalidTargetSize
  case invalidResponse
  case httpStatus(Int)
  case unsupportedImage
}

final class DecodedPhotoImage: @unchecked Sendable {
  let image: UIImage
  let memoryCost: Int

  init(image: UIImage, memoryCost: Int) {
    self.image = image
    self.memoryCost = memoryCost
  }
}

enum ImageDownsampler {
  static func decode(
    data: Data,
    maxPixelSize: Int,
    displayScale: CGFloat
  ) throws -> DecodedPhotoImage {
    guard maxPixelSize > 0,
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else {
      throw PhotoImagePipelineError.unsupportedImage
    }

    return try decode(
      source: source,
      maxPixelSize: maxPixelSize,
      displayScale: displayScale
    )
  }

  static func decodeToFill(
    data: Data,
    targetPixelSize: CGSize,
    displayScale: CGFloat
  ) throws -> DecodedPhotoImage {
    guard targetPixelSize.width > 0, targetPixelSize.height > 0,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let sourceSize = orientedPixelSize(of: source)
    else {
      throw PhotoImagePipelineError.unsupportedImage
    }

    let fillScale = max(
      targetPixelSize.width / sourceSize.width,
      targetPixelSize.height / sourceSize.height
    )
    let sourceLargestDimension = max(sourceSize.width, sourceSize.height)
    let maxPixelSize = Int(ceil(sourceLargestDimension * min(fillScale, 1)))
    return try decode(
      source: source,
      maxPixelSize: max(maxPixelSize, 1),
      displayScale: displayScale
    )
  }

  private static func decode(
    source: CGImageSource,
    maxPixelSize: Int,
    displayScale: CGFloat
  ) throws -> DecodedPhotoImage {

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      throw PhotoImagePipelineError.unsupportedImage
    }

    return DecodedPhotoImage(
      image: UIImage(cgImage: cgImage, scale: displayScale, orientation: .up),
      memoryCost: cgImage.bytesPerRow * cgImage.height
    )
  }

  private static func orientedPixelSize(of source: CGImageSource) -> CGSize? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else {
      return nil
    }

    let orientation =
      (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    if 5...8 ~= orientation {
      return CGSize(width: height, height: width)
    }
    return CGSize(width: width, height: height)
  }
}

enum PhotoImageSizing {
  static func targetPixelSize(for targetSize: CGSize, displayScale: CGFloat) -> CGSize? {
    guard targetSize.width.isFinite, targetSize.width > 0,
      targetSize.height.isFinite, targetSize.height > 0,
      displayScale.isFinite, displayScale > 0
    else {
      return nil
    }

    return CGSize(
      width: bucketedPixelDimension(targetSize.width * displayScale),
      height: bucketedPixelDimension(targetSize.height * displayScale)
    )
  }

  private static func bucketedPixelDimension(_ value: CGFloat) -> CGFloat {
    let requestedPixels = Int(ceil(value))
    let bucketSize = 64
    return CGFloat(((requestedPixels + bucketSize - 1) / bucketSize) * bucketSize)
  }
}

actor PhotoImagePipeline {
  private struct InFlightRequest {
    let task: Task<DecodedPhotoImage, Error>
    var waiters: Set<UUID>
  }

  static let shared: PhotoImagePipeline = {
    let responseCache = URLCache(
      memoryCapacity: 32 * 1_024 * 1_024,
      diskCapacity: 512 * 1_024 * 1_024,
      diskPath: "sensta-photo-cache"
    )
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.urlCache = responseCache
    configuration.httpMaximumConnectionsPerHost = 4
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = true

    return PhotoImagePipeline(
      session: URLSession(configuration: configuration),
      responseCache: responseCache,
      decodedMemoryCapacity: 96 * 1_024 * 1_024
    )
  }()

  private let session: URLSession
  private let responseCache: URLCache?
  private let decodedCache = NSCache<NSString, DecodedPhotoImage>()
  private var inFlightRequests: [String: InFlightRequest] = [:]

  init(
    session: URLSession,
    responseCache: URLCache?,
    decodedMemoryCapacity: Int
  ) {
    self.session = session
    self.responseCache = responseCache
    decodedCache.totalCostLimit = decodedMemoryCapacity
  }

  func image(
    for url: URL,
    targetSize: CGSize,
    displayScale: CGFloat
  ) async throws -> DecodedPhotoImage {
    guard
      let targetPixelSize = PhotoImageSizing.targetPixelSize(
        for: targetSize,
        displayScale: displayScale
      )
    else {
      throw PhotoImagePipelineError.invalidTargetSize
    }

    let cacheKey =
      "\(url.absoluteString)#\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))"
    if let cachedImage = decodedCache.object(forKey: NSString(string: cacheKey)) {
      return cachedImage
    }

    let waiterID = UUID()
    let requestTask: Task<DecodedPhotoImage, Error>
    if var request = inFlightRequests[cacheKey] {
      request.waiters.insert(waiterID)
      inFlightRequests[cacheKey] = request
      requestTask = request.task
    } else {
      requestTask = Task {
        try await loadAndDecode(
          url: url,
          targetPixelSize: targetPixelSize,
          displayScale: displayScale,
          cacheKey: cacheKey
        )
      }
      inFlightRequests[cacheKey] = InFlightRequest(
        task: requestTask,
        waiters: [waiterID]
      )
    }

    return try await withTaskCancellationHandler {
      do {
        let image = try await requestTask.value
        finishWaiter(waiterID, cacheKey: cacheKey)
        try Task.checkCancellation()
        return image
      } catch {
        finishWaiter(waiterID, cacheKey: cacheKey)
        throw error
      }
    } onCancel: {
      Task {
        await self.cancelWaiter(waiterID, cacheKey: cacheKey)
      }
    }
  }

  func prefetch(
    _ url: URL?,
    targetSize: CGSize,
    displayScale: CGFloat
  ) async {
    guard let url else { return }
    _ = try? await image(for: url, targetSize: targetSize, displayScale: displayScale)
  }

  private func loadAndDecode(
    url: URL,
    targetPixelSize: CGSize,
    displayScale: CGFloat,
    cacheKey: String
  ) async throws -> DecodedPhotoImage {

    var request = URLRequest(
      url: url,
      cachePolicy: .returnCacheDataElseLoad,
      timeoutInterval: 30
    )
    request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

    let data: Data
    var responseToCache: URLResponse?
    if let cachedResponse = responseCache?.cachedResponse(for: request) {
      data = cachedResponse.data
    } else {
      let response: URLResponse
      (data, response) = try await session.data(for: request)
      try Task.checkCancellation()

      guard let httpResponse = response as? HTTPURLResponse else {
        throw PhotoImagePipelineError.invalidResponse
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw PhotoImagePipelineError.httpStatus(httpResponse.statusCode)
      }
      responseToCache = response
    }

    let decodePriority = Task.currentPriority
    let decodedImage = try await Task.detached(priority: decodePriority) {
      try ImageDownsampler.decodeToFill(
        data: data,
        targetPixelSize: targetPixelSize,
        displayScale: displayScale
      )
    }.value
    try Task.checkCancellation()

    if let responseToCache {
      responseCache?.storeCachedResponse(
        CachedURLResponse(
          response: responseToCache,
          data: data,
          storagePolicy: .allowed
        ),
        for: request
      )
    }

    decodedCache.setObject(
      decodedImage,
      forKey: NSString(string: cacheKey),
      cost: decodedImage.memoryCost
    )
    return decodedImage
  }

  private func finishWaiter(_ waiterID: UUID, cacheKey: String) {
    guard var request = inFlightRequests[cacheKey] else { return }
    request.waiters.remove(waiterID)
    if request.waiters.isEmpty {
      inFlightRequests[cacheKey] = nil
    } else {
      inFlightRequests[cacheKey] = request
    }
  }

  private func cancelWaiter(_ waiterID: UUID, cacheKey: String) {
    guard var request = inFlightRequests[cacheKey] else { return }
    request.waiters.remove(waiterID)
    if request.waiters.isEmpty {
      request.task.cancel()
      inFlightRequests[cacheKey] = nil
    } else {
      inFlightRequests[cacheKey] = request
    }
  }
}

enum CachedPhotoImagePhase {
  case empty
  case success(Image)
  case failure
}

struct CachedAsyncPhotoImage<Content: View>: View {
  let url: URL?
  let targetSize: CGSize
  @ViewBuilder let content: (CachedPhotoImagePhase) -> Content

  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var loadedImage: UIImage?
  @State private var failed = false

  var body: some View {
    content(phase)
      .task(id: requestIdentity) {
        loadedImage = nil
        failed = false
        guard let url else {
          failed = true
          return
        }

        do {
          let clock = ContinuousClock()
          let startedAt = clock.now
          let decodedImage = try await PhotoImagePipeline.shared.image(
            for: url,
            targetSize: targetSize,
            displayScale: displayScale
          )
          try Task.checkCancellation()
          if !reduceMotion && startedAt.duration(to: clock.now) > .milliseconds(100) {
            withAnimation(.easeOut(duration: 0.16)) {
              loadedImage = decodedImage.image
            }
          } else {
            loadedImage = decodedImage.image
          }
        } catch is CancellationError {
          return
        } catch {
          failed = true
        }
      }
  }

  private var phase: CachedPhotoImagePhase {
    if let loadedImage {
      return .success(Image(uiImage: loadedImage))
    }
    return failed ? .failure : .empty
  }

  private var requestIdentity: String {
    let pixelSize =
      PhotoImageSizing.targetPixelSize(
        for: targetSize,
        displayScale: displayScale
      ) ?? .zero
    return "\(url?.absoluteString ?? "missing")#\(Int(pixelSize.width))x\(Int(pixelSize.height))"
  }
}
