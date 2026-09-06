import Foundation
import Observation
import SwiftUI

enum PhotoPostChange: Equatable {
  case edited(Int)
  case deleted(Int)
}

struct PhotoPostMutationResponse: Decodable {
  let success: Bool
  let code: Int

  func check() throws {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
  }
}

enum PhotoPostManagementEndpoint {
  private struct DeleteBody: Encodable {
    let boardUid: Int
    let postUid: Int
  }

  static func modify(
    baseURL: URL, detail: PhotoPostDetail, title: String, content: String, tags: [String],
    boundary: String = "sensta-edit-\(UUID().uuidString)"
  ) throws -> URLRequest {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let boardID = detail.boardID, let categoryID = detail.categoryID,
      boardID > 0, categoryID > 0, detail.post.id > 0, [0, 2].contains(detail.status),
      (2...299).contains(title.count), content.count >= 2,
      !boundary.isEmpty && !boundary.contains("\r") && !boundary.contains("\n")
    else { throw NuboAPIError.invalidRequest }

    var body = Data()
    func append(_ value: String) throws {
      guard let data = value.data(using: .utf8) else { throw NuboAPIError.invalidRequest }
      body.append(data)
    }
    func field(_ name: String, _ value: String) throws {
      try append("--\(boundary)\r\n")
      try append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      try append(value)
      try append("\r\n")
    }

    try field("boardUid", String(boardID))
    try field("postUid", String(detail.post.id))
    try field("categoryUid", String(categoryID))
    try field("isNotice", "false")
    try field("isSecret", detail.status == 2 ? "true" : "false")
    try field("title", title)
    try field("content", content)
    try field("tags", tags.joined(separator: ","))
    try append("--\(boundary)--\r\n")

    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "editor/modify", method: "PATCH")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("sensta-ios", forHTTPHeaderField: "X-Nubo-Client")
    request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
    request.httpBody = body
    return request
  }

  static func delete(baseURL: URL, boardID: Int, postID: Int) throws -> URLRequest {
    guard boardID > 0, postID > 0 else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "board/remove/post", method: "DELETE")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      DeleteBody(boardUid: boardID, postUid: postID))
    return request
  }
}

@MainActor @Observable
final class PhotoPostEditModel {
  static let maximumTagLength = PhotoUploadModel.maximumTagLength

  var title: String
  var content: String
  private(set) var tagDraft = ""
  private(set) var tags: [String]
  private(set) var suggestions: [PhotoUploadTagSuggestion] = []
  private(set) var tagFeedback: String?
  private(set) var isSaving = false
  private(set) var error: String?

  init(detail: PhotoPostDetail) {
    title = detail.post.title.nuboPlainText
    content = detail.post.content.nuboPlainText
    var seen = Set<String>()
    tags = detail.tags.compactMap { item in
      let value = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return value.isEmpty || !seen.insert(value).inserted ? nil : value
    }
  }

  var canSave: Bool {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    return !isSaving && (2...299).contains(title.count) && content.count >= 2
      && effectiveTags != nil
  }

  func updateTagDraft(_ value: String) {
    let value = value.lowercased()
    guard value.contains(where: Self.isTagSeparator) else {
      tagDraft = value
      tagFeedback = nil
      if suggestionQuery == nil { suggestions = [] }
      return
    }

    var fragment = ""
    var rejectedFragment: String?
    for character in value {
      if Self.isTagSeparator(character) {
        guard !fragment.isEmpty else { continue }
        if !appendTag(fragment) { rejectedFragment = rejectedFragment ?? fragment }
        fragment = ""
      } else {
        fragment.append(character)
      }
    }
    tagDraft = fragment.isEmpty ? rejectedFragment ?? "" : fragment
    suggestions = []
  }

  @discardableResult
  func commitTagDraft() -> Bool {
    guard !tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
    guard appendTag(tagDraft) else { return false }
    tagDraft = ""
    suggestions = []
    return true
  }

  func removeTag(_ tag: String) {
    tags.removeAll { $0 == tag }
    tagFeedback = nil
  }

  func selectSuggestion(_ suggestion: PhotoUploadTagSuggestion) {
    _ = appendTag(suggestion.name)
    tagDraft = ""
    suggestions = []
  }

  func loadSuggestions(using account: AccountSession) async {
    guard let query = suggestionQuery, let baseURL = account.apiBaseURL else {
      suggestions = []
      return
    }
    do {
      let request = try PhotoUploadEndpoint.tagSuggestions(baseURL: baseURL, query: query)
      let data = try await account.sendAuthenticated(request)
      let values = try JSONDecoder()
        .decode(AccountEnvelope<[PhotoUploadTagSuggestion]>.self, from: data).checked()
      try Task.checkCancellation()
      guard query == suggestionQuery else { return }
      suggestions = values.filter {
        !tags.contains($0.name.lowercased()) && Self.normalizedTag($0.name) != nil
      }
    } catch is CancellationError {
    } catch {
      if query == suggestionQuery { suggestions = [] }
    }
  }

  func save(detail: PhotoPostDetail, using account: AccountSession) async -> Bool {
    guard canSave, let baseURL = account.apiBaseURL,
      account.user?.uid == detail.post.writer.id, let tags = effectiveTags
    else { return false }
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      let request = try PhotoPostManagementEndpoint.modify(
        baseURL: baseURL, detail: detail, title: title, content: content, tags: tags)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(PhotoPostMutationResponse.self, from: data).check()
      try Task.checkCancellation()
      return true
    } catch is CancellationError {
      return false
    } catch {
      self.error = "사진 정보를 수정하지 못했어요. 입력 내용과 연결을 확인한 뒤 다시 시도해 주세요."
      return false
    }
  }

  private func appendTag(_ value: String) -> Bool {
    guard let tag = Self.normalizedTag(value) else {
      let count = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .removingLeadingHashtagsForEditing().count
      if count < 2 {
        tagFeedback = "태그는 2자 이상 입력해 주세요."
      } else if count > Self.maximumTagLength {
        tagFeedback = "태그는 30자까지 입력할 수 있어요."
      } else {
        tagFeedback = "태그에는 한글·영문·숫자·밑줄·마침표만 사용할 수 있어요."
      }
      return false
    }
    if !tags.contains(tag) { tags.append(tag) }
    tagFeedback = nil
    return true
  }

  private var effectiveTags: [String]? {
    let pending = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pending.isEmpty else { return tags }
    guard let pending = Self.normalizedTag(pending) else { return nil }
    return tags.contains(pending) ? tags : tags + [pending]
  }

  private var suggestionQuery: String? { Self.normalizedTag(tagDraft) }

  private static func normalizedTag(_ value: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .removingLeadingHashtagsForEditing().lowercased()
    guard (2...maximumTagLength).contains(value.count),
      value.range(of: #"^[a-z0-9가-힣_.]+$"#, options: .regularExpression) != nil
    else { return nil }
    return value
  }

  private static func isTagSeparator(_ character: Character) -> Bool {
    character == "," || character.isWhitespace
  }
}

struct PhotoPostEditSheet: View {
  let detail: PhotoPostDetail
  let account: AccountSession
  let onSaved: @MainActor () -> Void
  @State private var model: PhotoPostEditModel
  @State private var suggestionTask: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss

  @MainActor
  init(detail: PhotoPostDetail, account: AccountSession, onSaved: @escaping @MainActor () -> Void) {
    self.detail = detail
    self.account = account
    self.onSaved = onSaved
    _model = State(initialValue: PhotoPostEditModel(detail: detail))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("사진 정보") {
          TextField("사진 제목", text: $model.title)
            .accessibilityIdentifier("photo-edit-title")
          TextEditor(text: $model.content)
            .frame(minHeight: 130)
            .accessibilityLabel("사진 설명")
            .accessibilityIdentifier("photo-edit-content")
          Text("기존 사진은 그대로 유지됩니다.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("태그") {
          if !model.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 7) {
                ForEach(model.tags, id: \.self) { tag in
                  Button {
                    model.removeTag(tag)
                  } label: {
                    Label("#\(tag)", systemImage: "xmark")
                      .font(.subheadline)
                      .padding(.horizontal, 10)
                      .frame(minHeight: 32)
                      .background(.tint.opacity(0.12), in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("\(tag) 태그 삭제")
                  .accessibilityIdentifier("photo-edit-tag-\(tag)")
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
            .accessibilityIdentifier("photo-edit-tags")
            if !model.tagDraft.isEmpty {
              Button("태그 추가", systemImage: "plus.circle.fill") {
                model.commitTagDraft()
              }
              .labelStyle(.iconOnly)
              .accessibilityIdentifier("photo-edit-tag-add")
            }
          }

          ForEach(model.suggestions) { suggestion in
            Button {
              suggestionTask?.cancel()
              model.selectSuggestion(suggestion)
            } label: {
              HStack {
                Text("#\(suggestion.name)")
                Spacer()
                Text("\(suggestion.count)회").foregroundStyle(.secondary)
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photo-edit-tag-suggestion-\(suggestion.uid)")
          }

          Text(model.tagFeedback ?? "콤마·스페이스·Return으로 추가하고, 태그를 누르면 삭제할 수 있어요.")
            .font(.caption)
            .foregroundStyle(model.tagFeedback == nil ? Color.secondary : Color.red)
        }

        if let error = model.error {
          Section {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .accessibilityIdentifier("photo-edit-error")
          }
        }
      }
      .navigationTitle("사진 정보 수정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }.disabled(model.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(model.isSaving ? "저장 중…" : "저장") {
            Task {
              if await model.save(detail: detail, using: account) {
                onSaved()
                dismiss()
              }
            }
          }
          .disabled(!model.canSave)
          .accessibilityIdentifier("photo-edit-save")
        }
      }
    }
    .interactiveDismissDisabled(model.isSaving)
    .onChange(of: model.tagDraft) { _, _ in
      suggestionTask?.cancel()
      suggestionTask = Task {
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        await model.loadSuggestions(using: account)
      }
    }
    .onDisappear { suggestionTask?.cancel() }
  }
}

extension PhotoPostDetail {
  @MainActor
  func delete(using account: AccountSession) async throws {
    guard account.user?.uid == post.writer.id, let baseURL = account.apiBaseURL,
      let boardID, boardID > 0
    else { throw NuboAPIError.invalidRequest }
    let request = try PhotoPostManagementEndpoint.delete(
      baseURL: baseURL, boardID: boardID, postID: post.id)
    let data = try await account.sendAuthenticated(request)
    try JSONDecoder().decode(PhotoPostMutationResponse.self, from: data).check()
  }
}

extension String {
  fileprivate func removingLeadingHashtagsForEditing() -> String {
    String(drop(while: { $0 == "#" }))
  }
}
