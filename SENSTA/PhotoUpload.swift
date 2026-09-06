import Foundation
import ImageIO
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PreparedUploadPhoto: Identifiable, Equatable, Sendable {
  let id: UUID
  let fileURL: URL
  let previewData: Data
  let byteCount: Int
  let sourceFileURL: URL
  let sourcePreviewData: Data
  let sourceByteCount: Int
  let edits: PhotoUploadEdits

  init(
    id: UUID, fileURL: URL, previewData: Data, byteCount: Int,
    sourceFileURL: URL? = nil, sourcePreviewData: Data? = nil, sourceByteCount: Int? = nil,
    edits: PhotoUploadEdits = PhotoUploadEdits()
  ) {
    self.id = id
    self.fileURL = fileURL
    self.previewData = previewData
    self.byteCount = byteCount
    self.sourceFileURL = sourceFileURL ?? fileURL
    self.sourcePreviewData = sourcePreviewData ?? previewData
    self.sourceByteCount = sourceByteCount ?? byteCount
    self.edits = edits
  }

  func removeRenderedFile() {
    guard fileURL != sourceFileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  func removeFile() {
    removeRenderedFile()
    try? FileManager.default.removeItem(at: sourceFileURL)
  }
}

enum PhotoUploadPreparationError: Error {
  case unreadableImage
  case cannotWriteImage
}

enum PhotoUploadPreparer {
  static let maximumPixelSize = 4_096

  static func prepare(data: Data, id: UUID = UUID()) throws -> PreparedUploadPhoto {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary)
    else { throw PhotoUploadPreparationError.unreadableImage }

    let fileURL = FileManager.default.temporaryDirectory
      .appending(path: "sensta-upload-\(id.uuidString).jpg")
    guard
      let destination = CGImageDestinationCreateWithURL(
        fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw PhotoUploadPreparationError.cannotWriteImage }

    var properties =
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    // 공개 사진에는 촬영 정보는 남기되 정확한 좌표는 포함하지 않는다.
    properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
    properties[kCGImagePropertyOrientation] = 1
    properties[kCGImagePropertyPixelWidth] = image.width
    properties[kCGImagePropertyPixelHeight] = image.height
    properties[kCGImageDestinationLossyCompressionQuality] = 0.9
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: fileURL)
      throw PhotoUploadPreparationError.cannotWriteImage
    }

    let preview =
      UIImage(cgImage: image)
      .preparingThumbnail(of: CGSize(width: 360, height: 360))?
      .jpegData(compressionQuality: 0.78) ?? Data()
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
    return PreparedUploadPhoto(
      id: id, fileURL: fileURL, previewData: preview, byteCount: values.fileSize ?? 0)
  }
}

struct PhotoUploadCategory: Decodable, Identifiable, Equatable, Sendable {
  let uid: Int
  let name: String
  var id: Int { uid }
}

struct PhotoUploadEditorConfig: Equatable, Sendable {
  let boardID: Int
  let usesCategories: Bool
  let categories: [PhotoUploadCategory]
}

struct PhotoUploadConfigEnvelope: Decodable, Sendable {
  let success: Bool
  let error: String
  let code: Int
  let result: PhotoUploadConfigResultDTO?

  func checked() throws -> PhotoUploadEditorConfig {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result, result.config.uid > 0, !result.categories.isEmpty else {
      throw NuboAPIError.malformedResponse
    }
    return PhotoUploadEditorConfig(
      boardID: result.config.uid,
      usesCategories: result.config.useCategory,
      categories: result.categories)
  }
}

struct PhotoUploadConfigResultDTO: Decodable, Sendable {
  let config: PhotoUploadBoardConfigDTO
  let categories: [PhotoUploadCategory]
}

struct PhotoUploadBoardConfigDTO: Decodable, Sendable {
  let uid: Int
  let useCategory: Bool
}

struct PhotoUploadTagSuggestion: Decodable, Identifiable, Equatable, Sendable {
  let uid: Int
  let name: String
  let count: Int
  var id: Int { uid }
}

enum PhotoUploadEndpoint {
  static func config(baseURL: URL) throws -> URLRequest {
    guard
      var components = URLComponents(
        url: baseURL.appending(path: "editor/config"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [URLQueryItem(name: "id", value: "photo")]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func write(
    baseURL: URL, body: MultipartBodyFile, appVersion: String?
  ) -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: "editor/write"))
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue(
      "multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")
    request.setValue("sensta-ios", forHTTPHeaderField: "X-Nubo-Client")
    if let appVersion, !appVersion.isEmpty {
      request.setValue(appVersion, forHTTPHeaderField: "X-Nubo-App-Version")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func tagSuggestions(baseURL: URL, query: String, limit: Int = 10) throws -> URLRequest {
    guard limit > 0,
      var components = URLComponents(
        url: baseURL.appending(path: "editor/suggestion/tag"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "tag", value: query),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct MultipartBodyFile: Sendable {
  let fileURL: URL
  let boundary: String
  let byteCount: Int

  static func make(
    boardID: Int, categoryID: Int, title: String, content: String, tags: [String],
    photos: [PreparedUploadPhoto], boundary: String = "sensta-\(UUID().uuidString)"
  ) throws -> MultipartBodyFile {
    guard boardID > 0, categoryID > 0, !photos.isEmpty else {
      throw NuboAPIError.invalidRequest
    }
    let url = FileManager.default.temporaryDirectory
      .appending(path: "sensta-multipart-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
      throw PhotoUploadPreparationError.cannotWriteImage
    }
    let output = try FileHandle(forWritingTo: url)
    var completed = false
    defer {
      try? output.close()
      if !completed { try? FileManager.default.removeItem(at: url) }
    }

    func write(_ value: String) throws {
      guard let data = value.data(using: .utf8) else { throw NuboAPIError.invalidRequest }
      try output.write(contentsOf: data)
    }
    func field(_ name: String, _ value: String) throws {
      try write("--\(boundary)\r\n")
      try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      try write(value)
      try write("\r\n")
    }

    try field("boardUid", String(boardID))
    try field("categoryUid", String(categoryID))
    try field("isNotice", "false")
    try field("isSecret", "false")
    try field("title", title)
    try field("content", content)
    try field("tags", tags.joined(separator: ","))

    for (index, photo) in photos.enumerated() {
      try Task.checkCancellation()
      try write("--\(boundary)\r\n")
      try write(
        "Content-Disposition: form-data; name=\"attachments[]\"; filename=\"sensta-\(index + 1).jpg\"\r\n"
      )
      try write("Content-Type: image/jpeg\r\n\r\n")
      let input = try FileHandle(forReadingFrom: photo.fileURL)
      defer { try? input.close() }
      while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
        try Task.checkCancellation()
        try output.write(contentsOf: chunk)
      }
      try write("\r\n")
    }
    try write("--\(boundary)--\r\n")
    try output.synchronize()
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    completed = true
    return MultipartBodyFile(fileURL: url, boundary: boundary, byteCount: values.fileSize ?? 0)
  }

  func removeFile() { try? FileManager.default.removeItem(at: fileURL) }
}

@MainActor @Observable
final class PhotoUploadModel {
  static let maximumPhotoCount = 9
  static let maximumUploadBytes = 100 * 1_024 * 1_024
  static let maximumTagLength = 30
  static let policyVersion = "2026-08-21"
  static let policyPreferenceKey = "sensta.community-policy.accepted-version"

  var title = ""
  var content = ""
  private(set) var tagDraft = ""
  private(set) var tags: [String] = []
  private(set) var tagSuggestions: [PhotoUploadTagSuggestion] = []
  private(set) var tagFeedback: String?
  var selectedCategoryID = 0
  private(set) var photos: [PreparedUploadPhoto] = []
  private(set) var config: PhotoUploadEditorConfig?
  private(set) var isPreparing = false
  private(set) var isUploading = false
  private(set) var error: String?
  private(set) var isPolicyAccepted: Bool
  private var preparationIdentity = UUID()

  init(defaults: UserDefaults = .standard) {
    isPolicyAccepted =
      defaults.string(forKey: Self.policyPreferenceKey) == Self.policyVersion
  }

  var totalBytes: Int { photos.reduce(0) { $0 + $1.byteCount } }

  var canUpload: Bool {
    !isPreparing && !isUploading && config != nil && selectedCategoryID > 0
      && photos.count > 0 && photos.count <= Self.maximumPhotoCount
      && totalBytes <= Self.maximumUploadBytes
      && title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
      && content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
      && isPolicyAccepted && uploadTags != nil
  }

  var sizeDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
  }

  func setPolicyAccepted(_ accepted: Bool, defaults: UserDefaults = .standard) {
    isPolicyAccepted = accepted
    if accepted {
      defaults.set(Self.policyVersion, forKey: Self.policyPreferenceKey)
    } else {
      defaults.removeObject(forKey: Self.policyPreferenceKey)
    }
  }

  func updateTagDraft(_ value: String) {
    let value = value.lowercased()
    guard value.contains(where: Self.isTagSeparator) else {
      tagDraft = value
      tagFeedback = nil
      if suggestionQuery == nil { tagSuggestions = [] }
      return
    }

    var fragment = ""
    var rejectedFragment: String?
    for character in value {
      if Self.isTagSeparator(character) {
        guard !fragment.isEmpty else { continue }
        switch appendTag(fragment) {
        case .added, .duplicate:
          break
        case .rejected:
          rejectedFragment = rejectedFragment ?? fragment
        }
        fragment = ""
      } else {
        fragment.append(character)
      }
    }
    tagDraft = fragment.isEmpty ? rejectedFragment ?? "" : fragment
    tagSuggestions = []
  }

  @discardableResult
  func commitTagDraft() -> Bool {
    guard !tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
    switch appendTag(tagDraft) {
    case .added, .duplicate:
      tagDraft = ""
      tagSuggestions = []
      return true
    case .rejected:
      return false
    }
  }

  func selectTagSuggestion(_ suggestion: PhotoUploadTagSuggestion) {
    _ = appendTag(suggestion.name)
    tagDraft = ""
    tagSuggestions = []
  }

  func removeTag(_ tag: String) {
    tags.removeAll { $0 == tag }
    tagFeedback = nil
  }

  func loadTagSuggestions(using account: AccountSession) async {
    guard let query = suggestionQuery, let baseURL = account.apiBaseURL else {
      tagSuggestions = []
      return
    }
    do {
      let request = try PhotoUploadEndpoint.tagSuggestions(baseURL: baseURL, query: query)
      let data = try await account.sendAuthenticated(request)
      let values = try JSONDecoder()
        .decode(AccountEnvelope<[PhotoUploadTagSuggestion]>.self, from: data).checked()
      try Task.checkCancellation()
      guard query == suggestionQuery else { return }
      tagSuggestions = values.filter { value in
        !tags.contains(value.name.lowercased()) && Self.normalizedTag(value.name) != nil
      }
    } catch is CancellationError {
    } catch {
      if query == suggestionQuery { tagSuggestions = [] }
    }
  }

  func loadConfig(using account: AccountSession) async {
    guard config == nil, let baseURL = account.apiBaseURL else { return }
    do {
      let data = try await account.sendAuthenticated(PhotoUploadEndpoint.config(baseURL: baseURL))
      let config = try JSONDecoder().decode(PhotoUploadConfigEnvelope.self, from: data).checked()
      self.config = config
      selectedCategoryID = config.categories.first?.uid ?? 0
    } catch is CancellationError {
    } catch {
      self.error = "업로드 설정을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  func replaceSelection(_ items: [PhotosPickerItem]) async {
    guard items.count <= Self.maximumPhotoCount else { return }
    let identity = UUID()
    preparationIdentity = identity
    isPreparing = true
    error = nil
    defer {
      if preparationIdentity == identity { isPreparing = false }
    }
    let previous = photos
    photos = []
    for photo in previous { photo.removeFile() }
    var prepared: [PreparedUploadPhoto] = []
    do {
      for item in items {
        try Task.checkCancellation()
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw PhotoUploadPreparationError.unreadableImage
        }
        let photo = try await Task.detached(priority: .userInitiated) {
          try PhotoUploadPreparer.prepare(data: data)
        }.value
        prepared.append(photo)
      }
      try Task.checkCancellation()
      guard preparationIdentity == identity else {
        for photo in prepared { photo.removeFile() }
        return
      }
      photos = prepared
      if totalBytes > Self.maximumUploadBytes {
        error = "사진 크기가 100MB를 넘어요. 사진 수를 줄여 주세요."
      }
    } catch is CancellationError {
      for photo in prepared { photo.removeFile() }
    } catch {
      for photo in prepared { photo.removeFile() }
      if preparationIdentity == identity {
        self.error = "선택한 사진을 준비하지 못했어요. 다른 사진을 선택해 주세요."
      }
    }
  }

  func removePhoto(id: UUID) {
    guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
    photos[index].removeFile()
    photos.remove(at: index)
  }

  func applyEdits(to photoID: UUID, edits: PhotoUploadEdits) async -> Bool {
    guard let photo = photos.first(where: { $0.id == photoID }) else { return false }
    let identity = UUID()
    preparationIdentity = identity
    isPreparing = true
    error = nil
    var rendered: PreparedUploadPhoto?
    defer {
      if preparationIdentity == identity { isPreparing = false }
    }
    do {
      rendered = try await Task.detached(priority: .userInitiated) {
        try PhotoUploadRenderer.render(photo, edits: edits)
      }.value
      try Task.checkCancellation()
      guard preparationIdentity == identity,
        let index = photos.firstIndex(where: { $0.id == photoID }), let rendered
      else {
        rendered?.removeRenderedFile()
        return false
      }
      photos[index].removeRenderedFile()
      photos[index] = rendered
      if totalBytes > Self.maximumUploadBytes {
        error = "사진 크기가 100MB를 넘어요. 사진 수를 줄여 주세요."
      }
      return true
    } catch is CancellationError {
      rendered?.removeRenderedFile()
      return false
    } catch {
      rendered?.removeRenderedFile()
      if preparationIdentity == identity {
        self.error = "사진 편집 내용을 저장하지 못했어요. 다시 시도해 주세요."
      }
      return false
    }
  }

  #if DEBUG
    func installEditorFixtureIfNeeded() {
      guard photos.isEmpty else { return }
      let palettes: [(UIColor, UIColor)] = [
        (UIColor(red: 0.78, green: 0.31, blue: 0.20, alpha: 1), .systemTeal),
        (.systemIndigo, UIColor(red: 0.96, green: 0.74, blue: 0.25, alpha: 1)),
      ]
      photos = palettes.compactMap { leading, trailing in
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
          size: CGSize(width: 900, height: 600), format: format
        ).image { context in
          leading.setFill()
          context.fill(CGRect(x: 0, y: 0, width: 540, height: 600))
          trailing.setFill()
          context.fill(CGRect(x: 540, y: 0, width: 360, height: 600))
          UIColor.white.withAlphaComponent(0.8).setFill()
          context.cgContext.fillEllipse(in: CGRect(x: 110, y: 120, width: 190, height: 190))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return try? PhotoUploadPreparer.prepare(data: data)
      }
    }
  #endif

  func upload(using account: AccountSession) async -> Bool {
    guard canUpload, let config, let baseURL = account.apiBaseURL, let uploadTags else {
      return false
    }
    isUploading = true
    error = nil
    defer { isUploading = false }
    do {
      let body = try MultipartBodyFile.make(
        boardID: config.boardID, categoryID: selectedCategoryID,
        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
        tags: uploadTags, photos: photos)
      defer { body.removeFile() }
      let request = PhotoUploadEndpoint.write(
        baseURL: baseURL, body: body,
        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
          as? String)
      let data = try await account.uploadAuthenticated(request, fromFile: body.fileURL)
      let postID = try JSONDecoder().decode(AccountEnvelope<Int>.self, from: data).checked()
      guard postID > 0 else { throw NuboAPIError.malformedResponse }
      cleanUp()
      return true
    } catch is CancellationError {
      return false
    } catch {
      self.error = "사진을 올리지 못했어요. 입력 내용과 연결을 확인한 뒤 다시 시도해 주세요."
      return false
    }
  }

  func cleanUp() {
    preparationIdentity = UUID()
    isPreparing = false
    for photo in photos { photo.removeFile() }
    photos = []
    tagDraft = ""
    tags = []
    tagSuggestions = []
    tagFeedback = nil
  }

  private enum TagAdditionResult {
    case added
    case duplicate
    case rejected
  }

  private func appendTag(_ value: String) -> TagAdditionResult {
    guard let tag = Self.normalizedTag(value) else {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.removingLeadingHashtags().count < 2 {
        tagFeedback = "태그는 2자 이상 입력해 주세요."
      } else if trimmed.removingLeadingHashtags().count > Self.maximumTagLength {
        tagFeedback = "태그는 30자까지 입력할 수 있어요."
      } else {
        tagFeedback = "태그에는 한글·영문·숫자·밑줄·마침표만 사용할 수 있어요."
      }
      return .rejected
    }
    guard !tags.contains(tag) else {
      tagFeedback = "이미 추가한 태그예요."
      return .duplicate
    }
    tags.append(tag)
    tagFeedback = nil
    return .added
  }

  private var uploadTags: [String]? {
    let pending = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pending.isEmpty else { return tags }
    guard let pending = Self.normalizedTag(pending) else { return nil }
    return tags.contains(pending) ? tags : tags + [pending]
  }

  private var suggestionQuery: String? {
    Self.normalizedTag(tagDraft)
  }

  private static func normalizedTag(_ value: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .removingLeadingHashtags().lowercased()
    guard (2...maximumTagLength).contains(value.count),
      value.range(of: #"^[a-z0-9가-힣_.]+$"#, options: .regularExpression) != nil
    else { return nil }
    return value
  }

  private static func isTagSeparator(_ character: Character) -> Bool {
    character == "," || character.isWhitespace
  }
}

extension String {
  fileprivate func removingLeadingHashtags() -> String {
    String(drop(while: { $0 == "#" }))
  }
}

struct PhotoUploadView: View {
  let account: AccountSession
  let onUploaded: @MainActor () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var model = PhotoUploadModel()
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var preparationTask: Task<Void, Never>?
  @State private var tagSuggestionTask: Task<Void, Never>?
  @State private var editingPhoto: PreparedUploadPhoto?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          photoSection
          inputSection
          policySection
          if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle")
              .font(.footnote)
              .foregroundStyle(.red)
              .accessibilityIdentifier("photo-upload-error")
          }
          Button {
            Task {
              if await model.upload(using: account) { onUploaded() }
            }
          } label: {
            HStack {
              if model.isUploading { ProgressView().tint(.white) }
              Text(model.isUploading ? "사진을 올리는 중…" : "사진 공유하기")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .disabled(!model.canUpload)
          .accessibilityIdentifier("photo-upload-submit")
        }
        .padding(20)
      }
      .navigationTitle("새 사진")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }.disabled(model.isUploading)
        }
      }
    }
    .interactiveDismissDisabled(model.isUploading)
    .task {
      await model.loadConfig(using: account)
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-upload-editor") {
          model.installEditorFixtureIfNeeded()
        }
      #endif
    }
    .onChange(of: pickerItems) { _, items in
      preparationTask?.cancel()
      preparationTask = Task { await model.replaceSelection(items) }
    }
    .onChange(of: model.tagDraft) { _, _ in scheduleTagSuggestions() }
    .onDisappear {
      preparationTask?.cancel()
      tagSuggestionTask?.cancel()
      model.cleanUp()
    }
    .sheet(item: $editingPhoto) { photo in
      PhotoUploadEditorView(
        photo: photo,
        position: (model.photos.firstIndex(where: { $0.id == photo.id }) ?? 0) + 1,
        totalCount: model.photos.count
      ) { edits in
        await model.applyEdits(to: photo.id, edits: edits)
      }
    }
  }

  private var photoSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("사진").font(.headline)
        Spacer()
        Text(
          "\(model.photos.count)/\(PhotoUploadModel.maximumPhotoCount) · \(model.sizeDescription)"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if model.photos.isEmpty {
        PhotosPicker(
          selection: $pickerItems, maxSelectionCount: PhotoUploadModel.maximumPhotoCount,
          matching: .images
        ) {
          VStack(spacing: 10) {
            Image(systemName: "photo.badge.plus").font(.largeTitle)
            Text("사진 선택")
          }
          .frame(maxWidth: .infinity, minHeight: 150)
          .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo-upload-picker")
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
          ForEach(model.photos) { photo in
            ZStack(alignment: .topTrailing) {
              Button {
                editingPhoto = photo
              } label: {
                ZStack(alignment: .bottomLeading) {
                  if let image = UIImage(data: photo.previewData) {
                    Image(uiImage: image)
                      .resizable().scaledToFill()
                      .frame(maxWidth: .infinity)
                      .frame(height: 112).clipShape(RoundedRectangle(cornerRadius: 12))
                  }
                  Label(
                    photo.edits.needsRendering ? "편집됨" : "편집",
                    systemImage: "slider.horizontal.3"
                  )
                  .font(.caption2).fontWeight(.semibold)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8).padding(.vertical, 5)
                  .background(.black.opacity(0.58), in: Capsule())
                  .padding(6)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(
                "사진 \((model.photos.firstIndex(where: { $0.id == photo.id }) ?? 0) + 1) 편집"
              )
              .accessibilityValue(photo.edits.needsRendering ? "편집됨" : "원본")
              .accessibilityIdentifier(
                "photo-upload-edit-\(model.photos.firstIndex(where: { $0.id == photo.id }) ?? 0)")
              Button {
                model.removePhoto(id: photo.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.title3).symbolRenderingMode(.palette)
                  .foregroundStyle(.white, .black.opacity(0.65))
                  .frame(width: 44, height: 44)
              }
              .accessibilityLabel("사진 제거")
            }
          }
        }
        PhotosPicker(
          "사진 다시 선택", selection: $pickerItems,
          maxSelectionCount: PhotoUploadModel.maximumPhotoCount, matching: .images
        )
        .font(.subheadline)
      }
      if model.isPreparing { ProgressView("사진을 안전하게 준비하는 중…") }
      Text("사진을 눌러 회전·좌우 반전·필터를 적용할 수 있어요. 촬영 좌표는 업로드 전에 제거합니다.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var inputSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("게시글").font(.headline)
      TextField("사진 제목", text: $model.title)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("photo-upload-title")
      TextEditor(text: $model.content)
        .frame(minHeight: 110)
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("사진 설명")
        .accessibilityIdentifier("photo-upload-content")
      tagSection
      if let config = model.config, config.usesCategories {
        Picker("카테고리", selection: $model.selectedCategoryID) {
          ForEach(config.categories) { Text($0.name).tag($0.uid) }
        }
      }
      Text("제목과 설명은 각각 2자 이상 입력해 주세요.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var tagSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("태그").font(.subheadline).fontWeight(.medium)
      VStack(alignment: .leading, spacing: 8) {
        if !model.tags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
              ForEach(model.tags, id: \.self) { tag in
                Button {
                  model.removeTag(tag)
                } label: {
                  HStack(spacing: 5) {
                    Text("#\(tag)")
                    Image(systemName: "xmark")
                      .font(.caption2).fontWeight(.bold)
                  }
                  .font(.subheadline)
                  .padding(.horizontal, 10)
                  .frame(minHeight: 32)
                  .background(.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tag) 태그 삭제")
                .accessibilityIdentifier("photo-upload-tag-\(tag)")
              }
            }
          }
        }
        HStack(spacing: 8) {
          Image(systemName: "number").foregroundStyle(.secondary)
          TextField(
            "태그 입력",
            text: Binding(
              get: { model.tagDraft },
              set: { model.updateTagDraft($0) })
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.done)
          .onSubmit { model.commitTagDraft() }
          .accessibilityIdentifier("photo-upload-tags")
          if !model.tagDraft.isEmpty {
            Button {
              model.commitTagDraft()
            } label: {
              Image(systemName: "plus.circle.fill").font(.title3)
            }
            .accessibilityLabel("태그 추가")
            .accessibilityIdentifier("photo-upload-tag-add")
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.secondarySystemBackground))
      )
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))

      if !model.tagSuggestions.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(model.tagSuggestions.enumerated()), id: \.element.id) { index, suggestion in
            Button {
              tagSuggestionTask?.cancel()
              model.selectTagSuggestion(suggestion)
            } label: {
              HStack {
                Text("#\(suggestion.name)").foregroundStyle(.primary)
                Spacer()
                Text("\(suggestion.count)회").foregroundStyle(.secondary)
              }
              .font(.subheadline)
              .frame(maxWidth: .infinity, minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .accessibilityLabel("\(suggestion.name), \(suggestion.count)회 사용, 태그로 추가")
            .accessibilityIdentifier("photo-upload-tag-suggestion-\(suggestion.uid)")
            if index < model.tagSuggestions.count - 1 { Divider() }
          }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
      }

      Text(model.tagFeedback ?? "콤마·스페이스·Return으로 추가하고, 태그를 누르면 삭제할 수 있어요.")
        .font(.caption)
        .foregroundStyle(model.tagFeedback == nil ? Color.secondary : Color.red)
        .accessibilityIdentifier(
          model.tagFeedback == nil ? "photo-upload-tag-help" : "photo-upload-tag-error")
    }
  }

  private func scheduleTagSuggestions() {
    tagSuggestionTask?.cancel()
    tagSuggestionTask = Task {
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      await model.loadTagSuggestions(using: account)
    }
  }

  private var policySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(
        isOn: Binding(
          get: { model.isPolicyAccepted },
          set: { model.setPolicyAccepted($0) })
      ) {
        Text("커뮤니티 운영 원칙에 동의합니다")
      }
      .accessibilityIdentifier("photo-upload-policy")
      HStack(spacing: 14) {
        if let baseURL = account.apiBaseURL,
          let terms = URL(string: "/terms", relativeTo: baseURL),
          let privacy = URL(string: "/privacy", relativeTo: baseURL)
        {
          Link("이용약관", destination: terms)
          Link("개인정보처리방침", destination: privacy)
        }
      }
      .font(.caption)
    }
  }
}
