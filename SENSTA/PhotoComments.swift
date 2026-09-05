import Foundation
import Observation
import SwiftUI

struct PhotoComment: Identifiable, Equatable, Sendable {
  let id: Int
  let replyID: Int
  let writer: String
  let content: String
  let submitted: Date
  let likeCount: Int

  var isReply: Bool { replyID > 0 && replyID != id }
}

struct PhotoCommentsPage: Equatable, Sendable {
  let comments: [PhotoComment]
  let hasMore: Bool
}

protocol PhotoCommentsServing: Sendable {
  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage
}

enum PhotoCommentsEndpoint {
  static let pageSize = 30

  static func makeRequest(apiBaseURL: URL, boardID: Int, postID: Int, page: Int) throws
    -> URLRequest
  {
    guard boardID > 0, postID > 0, page > 0 else { throw NuboAPIError.invalidRequest }
    guard
      var components = URLComponents(
        url: apiBaseURL.appending(path: "comment/list"),
        resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "boardUid", value: String(boardID)),
      URLQueryItem(name: "postUid", value: String(postID)),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "limit", value: String(pageSize)),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct PhotoCommentsResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: ResultDTO?

  struct ResultDTO: Decodable {
    let boardUid: Int
    let totalCommentCount: Int
    let comments: [CommentDTO]
  }

  struct CommentDTO: Decodable {
    let uid: Int
    let replyUid: Int
    let postUid: Int
    let writer: BoardWriterDTO
    let like: Int
    let submitted: Int64
    let status: Int
    let content: String
  }

  func makePage(boardID: Int, postID: Int, page: Int) throws -> PhotoCommentsPage {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result, result.boardUid == boardID,
      result.comments.allSatisfy({ $0.postUid == postID })
    else { throw NuboAPIError.malformedResponse }
    // 익명 화면은 공개 댓글만 표시하며, 필터링 전 개수로 페이지 종료를 판단한다.
    let comments = result.comments.filter { $0.status == 0 }.map {
      PhotoComment(
        id: $0.uid, replyID: $0.replyUid, writer: $0.writer.name,
        content: $0.content == "(deleted)" ? "삭제된 댓글입니다." : $0.content.nuboPlainText,
        submitted: Date(timeIntervalSince1970: Double($0.submitted) / 1_000), likeCount: $0.like)
    }
    let limit = PhotoCommentsEndpoint.pageSize
    let lastPage =
      result.totalCommentCount / limit + (result.totalCommentCount % limit == 0 ? 0 : 1)
    return PhotoCommentsPage(
      comments: comments,
      hasMore: result.comments.count >= limit && page < lastPage)
  }
}

@MainActor
@Observable
final class PhotoCommentsViewModel {
  private let service: any PhotoCommentsServing
  private let boardID: Int
  private let postID: Int
  private var nextPage = 1
  private var retryResetsPage = true
  private(set) var comments: [PhotoComment] = []
  private(set) var isLoading = false
  private(set) var hasLoaded = false
  private(set) var hasMore = false
  private(set) var error: String?

  init(boardID: Int, postID: Int, service: any PhotoCommentsServing) {
    self.boardID = boardID
    self.postID = postID
    self.service = service
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    await load(reset: true)
  }

  func refresh() async { await load(reset: true) }
  func retry() async { await load(reset: retryResetsPage) }
  func loadMore() async {
    guard hasMore else { return }
    await load(reset: false)
  }

  private func load(reset: Bool) async {
    guard !isLoading else { return }
    isLoading = true
    retryResetsPage = reset
    error = nil
    defer { isLoading = false }
    do {
      var pageNumber = reset ? 1 : nextPage
      var updated = reset ? [] : comments
      var seen = Set(updated.map(\.id))
      let initialCount = updated.count
      while true {
        let page = try await service.fetchComments(
          boardID: boardID, postID: postID, page: pageNumber)
        try Task.checkCancellation()
        updated += page.comments.filter { seen.insert($0.id).inserted }
        pageNumber += 1
        if updated.count > initialCount || !page.hasMore {
          comments = updated
          hasLoaded = true
          hasMore = page.hasMore
          nextPage = pageNumber
          return
        }
      }
    } catch is CancellationError {
      return
    } catch {
      self.error = "댓글을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}

struct PhotoCommentsSection: View {
  @State private var model: PhotoCommentsViewModel

  init(boardID: Int, postID: Int, service: any PhotoCommentsServing) {
    _model = State(
      initialValue: PhotoCommentsViewModel(boardID: boardID, postID: postID, service: service))
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 24) {
      HStack {
        Text("댓글").font(.headline)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button("댓글 새로고침", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
          .labelStyle(.iconOnly)
          .foregroundStyle(.secondary)
          .disabled(model.isLoading)
      }
      if model.hasLoaded && model.comments.isEmpty {
        ContentUnavailableView("아직 공개 댓글이 없어요", systemImage: "bubble.left.and.bubble.right")
      }
      ForEach(model.comments) { comment in
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            if comment.isReply {
              Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("답글")
            }
            Text(comment.writer).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(comment.submitted, format: .dateTime.month().day())
              .font(.caption).foregroundStyle(.secondary)
          }
          Text(comment.content)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          if comment.likeCount > 0 {
            Label("\(comment.likeCount)", systemImage: "heart")
              .font(.caption).foregroundStyle(.secondary)
              .accessibilityLabel("좋아요 \(comment.likeCount)개")
          }
        }
        .padding(.leading, comment.isReply ? 20 : 0)
        Divider()
      }
      if model.isLoading {
        ProgressView().frame(maxWidth: .infinity)
      } else if let error = model.error {
        VStack(spacing: 12) {
          Text(error).foregroundStyle(.secondary)
          Button("다시 시도") {
            Task { await model.retry() }
          }
          .accessibilityIdentifier("photo-comments-retry")
        }
        .frame(maxWidth: .infinity)
      } else if model.hasMore {
        Button("댓글 더 보기") { Task { await model.loadMore() } }
          .frame(maxWidth: .infinity)
      }
    }
    .task { await model.loadIfNeeded() }
    .accessibilityIdentifier("photo-comments-section")
  }
}
