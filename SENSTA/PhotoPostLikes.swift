import Foundation
import Observation
import SwiftUI

struct PhotoLikeState: Equatable {
  var count: Int
  var isLiked = false
  var isBusy = false
  var isReady = false
  var error: String?
}

enum PhotoLikeEndpoint {
  static func request(baseURL: URL, boardID: Int, postID: Int, liked: Bool) throws -> URLRequest {
    guard boardID > 0, postID > 0 else { throw NuboAPIError.invalidRequest }
    struct Body: Encodable {
      let boardUid: Int
      let postUid: Int
      let liked: Bool
    }
    var request = try AccountEndpoint.request(baseURL: baseURL, path: "board/like", method: "PATCH")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      Body(boardUid: boardID, postUid: postID, liked: liked))
    return request
  }

  struct Response: Decodable {
    let success: Bool
    let code: Int
    func check() throws {
      guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    }
  }
}

@MainActor @Observable
final class PhotoPostLikes {
  private(set) var states: [Int: PhotoLikeState] = [:]
  private(set) var counts: [Int: Int] = [:]
  private var generation = UUID()

  func reset() {
    generation = UUID()
    states = [:]
  }

  func load(postID: Int, boardID: Int, fallbackCount: Int, account: AccountSession) async {
    guard account.user != nil, let baseURL = account.apiBaseURL,
      states[postID]?.isBusy != true, states[postID]?.isReady != true
    else { return }
    let generation = generation
    var state = states[postID] ?? PhotoLikeState(count: counts[postID] ?? fallbackCount)
    state.isBusy = true
    state.error = nil
    states[postID] = state
    do {
      let request = try PhotoPostDetailEndpoint.makeRequest(apiBaseURL: baseURL, postID: postID)
      let data = try await account.sendAuthenticated(request)
      let detail = try JSONDecoder().decode(BoardViewResponseDTO.self, from: data)
        .makePhotoPostDetail(apiBaseURL: baseURL)
      guard detail.post.id == postID, detail.boardID == boardID else {
        throw NuboAPIError.invalidResponse
      }
      try Task.checkCancellation()
      guard generation == self.generation else { return }
      states[postID] = PhotoLikeState(
        count: detail.post.likeCount, isLiked: detail.post.isLiked, isReady: true)
      counts[postID] = detail.post.likeCount
    } catch {
      guard generation == self.generation else { return }
      state.isBusy = false
      state.error = "좋아요 상태를 확인하지 못했어요. 다시 시도해 주세요."
      states[postID] = state
    }
  }

  func toggle(postID: Int, boardID: Int, account: AccountSession) async {
    guard account.user != nil, let baseURL = account.apiBaseURL,
      var state = states[postID], state.isReady, !state.isBusy
    else { return }
    let generation = generation
    let desired = !state.isLiked
    state.isBusy = true
    state.error = nil
    states[postID] = state
    do {
      let request = try PhotoLikeEndpoint.request(
        baseURL: baseURL, boardID: boardID, postID: postID, liked: desired)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(PhotoLikeEndpoint.Response.self, from: data).check()
      guard generation == self.generation else { return }
      state.count = max(0, state.count + (desired ? 1 : -1))
      state.isLiked = desired
      state.isBusy = false
      states[postID] = state
      counts[postID] = state.count
    } catch {
      guard generation == self.generation else { return }
      state.isBusy = false
      // 응답 유실 시 서버 반영 여부가 불명확하므로 다음 조작 전에 상태를 다시 조회한다.
      state.isReady = false
      state.error = "좋아요를 확인하지 못했어요. 상태를 다시 확인해 주세요."
      states[postID] = state
    }
  }
}

struct PhotoLikeButton: View {
  let post: PhotoPost
  let boardID: Int
  let account: AccountSession
  let detailService: any PhotoPostDetailServing
  @State private var showsLogin = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var state: PhotoLikeState? { account.postLikes.states[post.id] }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        guard account.user != nil else {
          showsLogin = true
          return
        }
        Task {
          if state?.isReady == true {
            await account.postLikes.toggle(postID: post.id, boardID: boardID, account: account)
          } else {
            await account.postLikes.load(
              postID: post.id, boardID: boardID, fallbackCount: post.likeCount, account: account)
          }
        }
      } label: {
        Label(
          (account.postLikes.counts[post.id] ?? post.likeCount).formatted(),
          systemImage: state?.isLiked == true ? "heart.fill" : "heart"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(state?.isLiked == true ? Color.red : Color.secondary)
        .frame(minHeight: 44)
      }
      .disabled(state?.isBusy == true)
      .accessibilityLabel(state?.isLiked == true ? "좋아요 취소" : "좋아요")
      .accessibilityValue("\(account.postLikes.counts[post.id] ?? post.likeCount)개")
      .accessibilityIdentifier("photo-detail-like")
      if state?.isBusy == true { ProgressView().accessibilityLabel("좋아요 확인 중") }
      if let error = state?.error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("상태 다시 확인") {
          Task {
            await account.postLikes.load(
              postID: post.id, boardID: boardID, fallbackCount: post.likeCount, account: account)
          }
        }.font(.caption).accessibilityIdentifier("photo-like-retry")
      }
    }
    .task(id: account.user?.uid) {
      await account.postLikes.load(
        postID: post.id, boardID: boardID, fallbackCount: post.likeCount, account: account)
    }
    .sheet(isPresented: $showsLogin) {
      AccountView(session: account, detailService: detailService)
        .environment(\.dynamicTypeSize, dynamicTypeSize).presentationDragIndicator(.visible)
    }
  }
}

private struct AccountEnvironmentKey: EnvironmentKey {
  static let defaultValue: AccountSession? = nil
}

extension EnvironmentValues {
  var accountSession: AccountSession? {
    get { self[AccountEnvironmentKey.self] }
    set { self[AccountEnvironmentKey.self] = newValue }
  }
}
