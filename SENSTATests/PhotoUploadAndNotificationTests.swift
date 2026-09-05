import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import SENSTA

@Suite(.serialized)
struct PhotoUploadAndNotificationTests {
  @Test
  func notificationContractMapsUnreadActivityAndBuildsScopedRoutes() throws {
    let baseURL = try #require(URL(string: "https://sensta.me/goapi/"))
    let data = Data(
      #"{"success":true,"error":"","code":0,"result":[{"uid":77,"fromUser":{"uid":9,"name":"빛","profile":"/upload/profile/9.webp"},"type":2,"id":"photo","boardType":1,"postUid":101,"checked":false,"timestamp":1788600000000}]}"#
        .utf8)
    let notifications = try JSONDecoder().decode(PhotoNotificationResponseDTO.self, from: data)
      .makeNotifications(apiBaseURL: baseURL)
    let notification = try #require(notifications.first)
    #expect(notification.id == 77)
    #expect(notification.senderName == "빛")
    #expect(notification.message == "내 게시글에 댓글을 남겼습니다")
    #expect(!notification.isRead)
    #expect(notification.postID == 101)
    #expect(
      notification.senderProfileURL?.absoluteString
        == "https://sensta.me/upload/profile/9.webp")

    let list = try PhotoNotificationEndpoint.list(baseURL: baseURL, limit: 20)
    #expect(list.url?.path == "/goapi/home/noti/load")
    #expect(list.url?.query == "limit=20")
    #expect(list.httpMethod == "GET")
    #expect(list.value(forHTTPHeaderField: "Authorization") == nil)
    let read = try PhotoNotificationEndpoint.markRead(baseURL: baseURL, notificationID: 77)
    #expect(read.url?.path == "/goapi/home/noti/checked/77")
    #expect(read.httpMethod == "PATCH")
    #expect(throws: NuboAPIError.invalidRequest) {
      try PhotoNotificationEndpoint.markRead(baseURL: baseURL, notificationID: 0)
    }
  }

  @Test
  func editorConfigUsesServerBoardAndCategoryInsteadOfHardCodingThem() throws {
    let data = Data(
      #"{"success":true,"error":"","code":0,"result":{"config":{"uid":42,"useCategory":true},"categories":[{"uid":8,"name":"풍경"},{"uid":9,"name":"인물"}]}}"#
        .utf8)
    let config = try JSONDecoder().decode(PhotoUploadConfigEnvelope.self, from: data).checked()
    #expect(config.boardID == 42)
    #expect(config.usesCategories)
    #expect(config.categories.map(\.uid) == [8, 9])
  }

  @Test
  func uploadRequestUsesAndroidMultipartContractAndIOSOrigin() throws {
    let photoURL = FileManager.default.temporaryDirectory
      .appending(path: "multipart-test-\(UUID().uuidString).jpg")
    try Data("jpeg-test-data".utf8).write(to: photoURL)
    let photo = PreparedUploadPhoto(
      id: UUID(), fileURL: photoURL, previewData: Data(), byteCount: 14)
    defer { photo.removeFile() }
    let body = try MultipartBodyFile.make(
      boardID: 2, categoryID: 5, title: "빛과 여백", content: "사진 설명",
      tags: ["빛", "daily"], photos: [photo], boundary: "test-boundary")
    defer { body.removeFile() }
    let text = String(decoding: try Data(contentsOf: body.fileURL), as: UTF8.self)
    #expect(text.contains("name=\"boardUid\"\r\n\r\n2"))
    #expect(text.contains("name=\"categoryUid\"\r\n\r\n5"))
    #expect(text.contains("name=\"title\"\r\n\r\n빛과 여백"))
    #expect(text.contains("name=\"tags\"\r\n\r\n빛,daily"))
    #expect(text.contains("name=\"attachments[]\"; filename=\"sensta-1.jpg\""))
    #expect(text.contains("jpeg-test-data"))
    #expect(text.hasSuffix("--test-boundary--\r\n"))

    let request = PhotoUploadEndpoint.write(
      baseURL: try #require(URL(string: "https://sensta.me/goapi/")), body: body,
      appVersion: "1.0")
    #expect(request.url?.path == "/goapi/editor/write")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "X-Nubo-Client") == "sensta-ios")
    #expect(request.value(forHTTPHeaderField: "X-Nubo-App-Version") == "1.0")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")
        == "multipart/form-data; boundary=test-boundary")
    #expect(request.value(forHTTPHeaderField: "Content-Length") == String(body.byteCount))
    #expect(request.httpBody == nil)
  }

  @Test
  func jpegPreparationNormalizesOrientationRemovesGPSAndPreservesExif() throws {
    let source = try makeImageData(type: UTType.jpeg, orientation: 6)
    let prepared = try PhotoUploadPreparer.prepare(data: source)
    defer { prepared.removeFile() }
    let output = try #require(CGImageSourceCreateWithURL(prepared.fileURL as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
    let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])

    #expect(image.width == 80)
    #expect(image.height == 120)
    #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:06 01:23:45")
    #expect(prepared.byteCount > 0)
    #expect(!prepared.previewData.isEmpty)
  }

  @Test
  func heicSelectionIsConvertedToUploadJPEGWhenEncoderIsAvailable() throws {
    guard let source = try makeOptionalImageData(type: UTType.heic, orientation: 1) else { return }
    let prepared = try PhotoUploadPreparer.prepare(data: source)
    defer { prepared.removeFile() }
    let output = try #require(CGImageSourceCreateWithURL(prepared.fileURL as CFURL, nil))
    #expect(CGImageSourceGetType(output) as String? == UTType.jpeg.identifier)
  }

  private func makeImageData(type: UTType, orientation: Int) throws -> Data {
    let data = try makeOptionalImageData(type: type, orientation: orientation)
    return try #require(data)
  }

  private func makeOptionalImageData(type: UTType, orientation: Int) throws -> Data? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format)
      .image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
      }
    let cgImage = try #require(image.cgImage)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, type.identifier as CFString, 1, nil)
    else { return nil }
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation,
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2026:09:06 01:23:45"
      ],
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 37.5665,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 126.978,
        kCGImagePropertyGPSLongitudeRef: "E",
      ],
    ]
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
