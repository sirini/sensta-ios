import Foundation
import Observation
import SwiftUI

enum PhotoCommentWriteEndpoint {
  static func request(baseURL: URL, boardID: Int, postID: Int, content: String, replyID: Int?)
    throws -> URLRequest
  {
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard boardID > 0, postID > 0, content.utf16.count >= 10, replyID == nil || replyID! > 0 else {
      throw NuboAPIError.invalidRequest
    }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: replyID == nil ? "comment/write" : "comment/reply", method: "POST")
    var fields = [("boardUid", String(boardID)), ("postUid", String(postID)), ("content", content)]
    if let replyID { fields.append(("replyTargetUid", String(replyID))) }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    request.httpBody = Data(
      fields.map { name, value in
        "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
      }.joined(separator: "&").utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    return request
  }
}

@MainActor @Observable
final class PhotoCommentComposerModel {
  var text = ""
  var reply: PhotoComment?
  private(set) var isSending = false
  private(set) var error: String?
  private(set) var needsRetryConfirmation = false
  private var generation = UUID()
  var hasMinimumLength: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= 10
  }
  var canSend: Bool {
    !isSending && hasMinimumLength
  }

  func reset() {
    generation = UUID()
    text = ""
    reply = nil
    error = nil
    needsRetryConfirmation = false
    isSending = false
  }

  func send(account: AccountSession, boardID: Int, postID: Int, allowRetry: Bool = false) async
    -> PhotoComment?
  {
    guard canSend, !needsRetryConfirmation || allowRetry,
      let user = account.user, let baseURL = account.apiBaseURL
    else { return nil }
    let generation = generation
    let identity = account.sessionIdentity
    let submitted = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let replyID = reply?.id
    isSending = true
    error = nil
    defer { if generation == self.generation { isSending = false } }
    do {
      let request = try PhotoCommentWriteEndpoint.request(
        baseURL: baseURL, boardID: boardID, postID: postID, content: submitted, replyID: replyID)
      let data = try await account.sendAuthenticated(request)
      let id = try JSONDecoder().decode(AccountEnvelope<Int>.self, from: data).checked()
      guard id > 0 else { throw NuboAPIError.malformedResponse }
      guard generation == self.generation, identity == account.sessionIdentity else { return nil }
      text = ""
      reply = nil
      needsRetryConfirmation = false
      return PhotoComment(
        id: id, replyID: replyID ?? id, writer: user.name.nuboPlainText,
        content: submitted.nuboPlainText, submitted: .now, likeCount: 0, writerID: user.uid)
    } catch {
      guard generation == self.generation, identity == account.sessionIdentity else { return nil }
      if case NuboAPIError.server = error {
        self.error = "댓글을 등록하지 못했어요. 내용이나 작성 권한을 확인해 주세요."
        needsRetryConfirmation = false
      } else {
        self.error = "전송 결과를 확인하지 못했어요. 댓글 목록에서 등록 여부를 확인해 주세요. 초안은 보관하고 있어요."
        needsRetryConfirmation = true
      }
      return nil
    }
  }
}

struct PhotoCommentComposer: View {
  @Bindable var model: PhotoCommentComposerModel
  let onSend: (Bool) -> Void
  @FocusState private var focused: Bool
  @State private var confirmsRetry = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let reply = model.reply {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(reply.writer)님에게 답글").font(.subheadline.weight(.medium))
            Text(reply.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
          Spacer()
          Button("답글 취소", systemImage: "xmark.circle.fill") { model.reply = nil }
            .labelStyle(.iconOnly).disabled(model.isSending)
        }
      }
      TextField(
        model.reply == nil ? "사진에 대한 이야기를 남겨보세요" : "답글을 입력하세요", text: $model.text, axis: .vertical
      )
      .lineLimit(3...6).focused($focused)
      .disabled(model.isSending).accessibilityIdentifier("comment-draft")
      .padding(12).background(
        Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
      HStack {
        if !model.hasMinimumLength {
          Text("10자 이상 입력해 주세요").font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("comment-minimum-length")
        }
        Spacer()
        if model.isSending { ProgressView().accessibilityLabel("댓글 전송 중") }
        Button(model.reply == nil ? "댓글 등록" : "답글 등록", systemImage: "arrow.up.circle.fill") {
          if model.needsRetryConfirmation {
            confirmsRetry = true
          } else {
            focused = false
            onSend(false)
          }
        }
        .disabled(!model.canSend).accessibilityIdentifier("comment-send")
      }
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(
          "comment-write-error")
      }
    }
    .onChange(of: model.reply?.id) { _, id in if id != nil { focused = true } }
    .confirmationDialog("댓글 목록을 확인하셨나요?", isPresented: $confirmsRetry, titleVisibility: .visible) {
      Button("등록되지 않은 것을 확인했어요. 다시 전송") {
        focused = false
        onSend(true)
      }
    } message: {
      Text("이미 등록됐다면 다시 전송할 때 댓글이 중복될 수 있어요.")
    }
  }
}
