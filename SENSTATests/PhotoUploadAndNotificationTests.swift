import CoreImage
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

  @Test @MainActor
  func uploadTagsBecomeRemovableChipsWithCommaSpaceAndReturnInput() throws {
    let defaults = try #require(UserDefaults(suiteName: "photo-upload-tags-\(UUID().uuidString)"))
    let model = PhotoUploadModel(defaults: defaults)

    model.updateTagDraft("풍경,DAILY #여름사진 ")
    #expect(model.tags == ["풍경", "daily", "여름사진"])
    #expect(model.tagDraft.isEmpty)

    model.removeTag("daily")
    #expect(model.tags == ["풍경", "여름사진"])

    model.updateTagDraft("밤사진")
    #expect(model.commitTagDraft())
    #expect(model.tags == ["풍경", "여름사진", "밤사진"])

    model.updateTagDraft("풍경 ")
    #expect(model.tags == ["풍경", "여름사진", "밤사진"])
    #expect(model.tagFeedback == "이미 추가한 태그예요.")
  }

  @Test @MainActor
  func uploadTagValidationKeepsRejectedDraftAvailableForCorrection() throws {
    let defaults = try #require(
      UserDefaults(suiteName: "photo-upload-invalid-tag-\(UUID().uuidString)"))
    let model = PhotoUploadModel(defaults: defaults)

    model.updateTagDraft("빛 ")
    #expect(model.tags.isEmpty)
    #expect(model.tagDraft == "빛")
    #expect(model.tagFeedback == "태그는 2자 이상 입력해 주세요.")

    model.updateTagDraft("bad-tag")
    #expect(!model.commitTagDraft())
    #expect(model.tagDraft == "bad-tag")
    #expect(model.tagFeedback?.contains("한글·영문") == true)
  }

  @Test
  func uploadTagSuggestionContractEncodesQueryAndUsageCount() throws {
    let baseURL = try #require(URL(string: "https://sensta.me/goapi/"))
    let request = try PhotoUploadEndpoint.tagSuggestions(
      baseURL: baseURL, query: "여름 사진", limit: 5)
    let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
      .queryItems
    #expect(request.url?.path == "/goapi/editor/suggestion/tag")
    #expect(query?.first(where: { $0.name == "tag" })?.value == "여름 사진")
    #expect(query?.first(where: { $0.name == "limit" })?.value == "5")
    #expect(request.httpMethod == "GET")

    let data = Data(
      #"{"success":true,"error":"","code":0,"result":[{"uid":31,"name":"여름사진","count":12}]}"#
        .utf8)
    let suggestions = try JSONDecoder()
      .decode(AccountEnvelope<[PhotoUploadTagSuggestion]>.self, from: data).checked()
    #expect(suggestions == [PhotoUploadTagSuggestion(uid: 31, name: "여름사진", count: 12)])
  }

  @Test
  func uploadEditStateKeepsAndroidCompatibleRotationMirrorAndFilterControls() {
    var edits = PhotoUploadEdits()
    let crop = PhotoUploadCrop(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
    edits.setCrop(crop)
    edits.rotateClockwise()
    #expect(edits.rotationDegrees == 90)
    edits.toggleMirror()
    edits.selectFilter(.warm)
    edits.setFilterIntensity(2)
    #expect(edits.isMirrored)
    #expect(edits.filter == .warm)
    #expect(edits.filterIntensity == 1)
    #expect(edits.crop == crop)
    #expect(edits.needsRendering)

    edits.rotateClockwise()
    edits.rotateClockwise()
    edits.rotateClockwise()
    #expect(edits.rotationDegrees == 0)
    edits.setFilterIntensity(-1)
    #expect(edits.filterIntensity == 0)

    edits.reset()
    #expect(edits == PhotoUploadEdits())
    #expect(!edits.needsRendering)
  }

  @Test
  func uploadCropPresetsAndGesturesStayInsideNormalizedSource() {
    let sourceSize = CGSize(width: 120, height: 80)
    let portrait = PhotoUploadCrop.centered(for: .portrait45, sourceSize: sourceSize)
    #expect(abs(portrait.x - 0.233_333) < 0.000_01)
    #expect(portrait.y == 0)
    #expect(abs(portrait.width - 0.533_333) < 0.000_01)
    #expect(portrait.height == 1)

    let moved = portrait.moved(byX: -1, y: 1)
    #expect(moved.x == 0)
    #expect(moved.y == 0)
    let resized = moved.resized(
      from: .bottomTrailing, to: CGPoint(x: 0.3, y: 0.4),
      aspect: .free, sourceSize: sourceSize)
    #expect(resized.x == 0)
    #expect(resized.y == 0)
    #expect(abs(resized.width - 0.3) < 0.000_01)
    #expect(abs(resized.height - 0.4) < 0.000_01)
  }

  @Test
  func uploadRendererAppliesEditsAndKeepsPrivacySafeMetadata() throws {
    let source = try makeImageData(type: UTType.jpeg, orientation: 1)
    let prepared = try PhotoUploadPreparer.prepare(data: source)
    var edits = PhotoUploadEdits()
    edits.setCrop(PhotoUploadCrop(x: 0.25, y: 0, width: 0.5, height: 1))
    edits.rotateClockwise()
    edits.toggleMirror()
    edits.selectFilter(.mono)
    let rendered = try PhotoUploadRenderer.render(prepared, edits: edits)
    defer { rendered.removeFile() }

    let output = try #require(CGImageSourceCreateWithURL(rendered.fileURL as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
    let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
    let average = try averageRGBA(of: rendered.fileURL)

    #expect(image.width == 80)
    #expect(image.height == 60)
    #expect(rendered.fileURL != rendered.sourceFileURL)
    #expect(rendered.edits == edits)
    #expect(!rendered.previewData.isEmpty)
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:06 01:23:45")
    #expect(abs(Int(average[0]) - Int(average[1])) <= 2)
    #expect(abs(Int(average[1]) - Int(average[2])) <= 2)
  }

  @Test
  func uploadRendererCropsOriginalPixelsBeforeOtherEdits() throws {
    let prepared = try PhotoUploadPreparer.prepare(data: makeQuadrantImageData())
    var edits = PhotoUploadEdits()
    edits.setCrop(PhotoUploadCrop(x: 0, y: 0, width: 0.5, height: 0.5))
    let rendered = try PhotoUploadRenderer.render(prepared, edits: edits)
    defer { rendered.removeFile() }

    let output = try #require(CGImageSourceCreateWithURL(rendered.fileURL as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
    let average = try averageRGBA(of: rendered.fileURL)
    #expect(image.width == 60)
    #expect(image.height == 40)
    #expect(average[0] > 200)
    #expect(average[1] < 40)
    #expect(average[2] < 40)
  }

  @Test @MainActor
  func uploadModelKeepsPerPhotoCropAndCleansReplacedRenders() async throws {
    let defaults = try #require(UserDefaults(suiteName: "photo-upload-crop-\(UUID().uuidString)"))
    let model = PhotoUploadModel(defaults: defaults)
    model.installEditorFixtureIfNeeded()
    let first = try #require(model.photos.first)
    let second = try #require(model.photos.last)
    let firstSourceURL = first.sourceFileURL
    let secondSourceURL = second.sourceFileURL
    var edits = PhotoUploadEdits()
    edits.setCrop(PhotoUploadCrop(x: 0.2, y: 0, width: 0.6, height: 1))

    #expect(await model.applyEdits(to: first.id, edits: edits))
    let firstRenderedURL = try #require(model.photos.first?.fileURL)
    #expect(firstRenderedURL != firstSourceURL)
    #expect(model.photos.first?.edits.crop == edits.crop)
    #expect(model.photos.last?.edits == PhotoUploadEdits())

    edits.rotateClockwise()
    #expect(await model.applyEdits(to: first.id, edits: edits))
    #expect(!FileManager.default.fileExists(atPath: firstRenderedURL.path))
    #expect(FileManager.default.fileExists(atPath: firstSourceURL.path))
    #expect(FileManager.default.fileExists(atPath: secondSourceURL.path))

    model.cleanUp()
    #expect(model.photos.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: firstSourceURL.path))
    #expect(!FileManager.default.fileExists(atPath: secondSourceURL.path))
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

  private func makeQuadrantImageData() throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format)
      .image { context in
        UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 40, width: 60, height: 40))
        UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
        context.fill(CGRect(x: 60, y: 0, width: 60, height: 40))
        UIColor(red: 1, green: 1, blue: 0, alpha: 1).setFill()
        context.fill(CGRect(x: 60, y: 40, width: 60, height: 40))
      }
    return try #require(image.jpegData(compressionQuality: 0.96))
  }

  private func averageRGBA(of fileURL: URL) throws -> [UInt8] {
    let input = try #require(CIImage(contentsOf: fileURL))
    let filter = try #require(CIFilter(name: "CIAreaAverage"))
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
    let output = try #require(filter.outputImage)
    var bytes = [UInt8](repeating: 0, count: 4)
    CIContext().render(
      output, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    return bytes
  }
}
