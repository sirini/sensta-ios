import Foundation
import SwiftUI

enum PhotoCommentManagementEndpoint {
  struct Response: Decodable {
    let success: Bool
    let code: Int

    func check() throws {
      guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    }
  }

  static func modifyRequest(
    baseURL: URL, boardID: Int, postID: Int, commentID: Int, content: String
  ) throws -> URLRequest {
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard boardID > 0, postID > 0, commentID > 0, content.utf16.count >= 2 else {
      throw NuboAPIError.invalidRequest
    }
    struct Body: Encodable {
      let boardUid: Int
      let postUid: Int
      let modifyTargetUid: Int
      let content: String
    }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "comment/modify", method: "PATCH")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      Body(
        boardUid: boardID, postUid: postID, modifyTargetUid: commentID,
        content: content.nuboSafeCommentHTML))
    return request
  }

  static func removeRequest(baseURL: URL, boardID: Int, commentID: Int) throws -> URLRequest {
    guard boardID > 0, commentID > 0 else { throw NuboAPIError.invalidRequest }
    guard
      var components = URLComponents(
        url: baseURL.appending(path: "comment/remove"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "boardUid", value: String(boardID)),
      URLQueryItem(name: "removeTargetUid", value: String(commentID)),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "comment/remove", method: "DELETE")
    request.url = url
    return request
  }
}

extension String {
  var nuboSafeCommentHTML: String {
    replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}

struct PhotoCommentEditorSheet: View {
  let comment: PhotoComment
  let isSaving: Bool
  let error: String?
  let onSave: (String) -> Void
  @State private var text: String
  @Environment(\.dismiss) private var dismiss

  init(
    comment: PhotoComment, isSaving: Bool, error: String?, onSave: @escaping (String) -> Void
  ) {
    self.comment = comment
    self.isSaving = isSaving
    self.error = error
    self.onSave = onSave
    _text = State(initialValue: comment.content)
  }

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSave: Bool {
    !isSaving && trimmed.utf16.count >= 2 && trimmed != comment.content
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("댓글 내용") {
          TextField("수정할 댓글을 입력해 주세요", text: $text, axis: .vertical)
            .lineLimit(5...12)
            .disabled(isSaving)
            .accessibilityIdentifier("comment-edit-draft")
          if trimmed.utf16.count < 2 {
            Text("2자 이상 입력해 주세요")
              .font(.caption).foregroundStyle(.secondary)
              .accessibilityIdentifier("comment-edit-minimum-length")
          }
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.secondary)
              .accessibilityIdentifier("comment-edit-error")
          }
        }
      }
      .navigationTitle("댓글 수정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("저장") { onSave(trimmed) }
            .disabled(!canSave)
            .accessibilityIdentifier("comment-edit-save")
        }
      }
      .overlay {
        if isSaving { ProgressView("댓글 수정 중") }
      }
      .senstaScreenStyle()
    }
    .interactiveDismissDisabled(isSaving)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
