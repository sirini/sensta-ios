import Foundation
import Observation
import SwiftUI

struct UserSafetyState: Equatable {
  var isReported = false
  var isBlocked = false
  var isReady = false
  var isLoading = false
  var isMutating = false
  var error: String?
}

enum UserReportContext: Equatable {
  case user
  case photo(postID: Int)

  func content(reason: String) throws -> String {
    let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard reason.utf16.count >= 5, reason.utf16.count <= 500 else {
      throw NuboAPIError.invalidRequest
    }
    switch self {
    case .user:
      return "사용자 신고: \(reason)"
    case .photo(let postID):
      guard postID > 0 else { throw NuboAPIError.invalidRequest }
      return "사진 #\(postID) 신고: \(reason)"
    }
  }
}

enum UserSafetyEndpoint {
  private struct ReportBody: Encodable {
    let targetUserUid: Int
    let checkedBlackList: Bool
    let content: String
  }

  private struct BlockBody: Encodable { let targetUserUid: Int }

  struct StatusResponse: Decodable {
    let success: Bool
    let code: Int
    let error: String?
    let result: Result?

    struct Result: Decodable {
      let isReported: Bool
      let isBannedByMe: Bool
    }

    func checked() throws -> UserSafetyState {
      guard success, code == 0 else {
        throw NuboAPIError.server(code: code, message: "")
      }
      guard let result else { throw NuboAPIError.malformedResponse }
      return UserSafetyState(
        isReported: result.isReported, isBlocked: result.isBannedByMe, isReady: true)
    }
  }

  struct MutationResponse: Decodable {
    let success: Bool
    let code: Int

    func check() throws {
      guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    }
  }

  static func status(baseURL: URL, targetUserID: Int) throws -> URLRequest {
    guard targetUserID > 0,
      var components = URLComponents(
        url: baseURL.appending(path: "auth/user/report"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "targetUserUid", value: String(targetUserID))
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(baseURL: baseURL, path: "auth/user/report")
    request.url = url
    return request
  }

  static func report(
    baseURL: URL, targetUserID: Int, context: UserReportContext, reason: String
  ) throws -> URLRequest {
    guard targetUserID > 0 else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "auth/user/report", method: "POST")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      ReportBody(
        targetUserUid: targetUserID, checkedBlackList: false,
        content: try context.content(reason: reason)))
    return request
  }

  static func block(baseURL: URL, targetUserID: Int, blocked: Bool) throws -> URLRequest {
    guard targetUserID > 0 else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "auth/user/block", method: blocked ? "PUT" : "DELETE")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(BlockBody(targetUserUid: targetUserID))
    return request
  }
}

@MainActor @Observable
final class UserSafetyCenter {
  private(set) var states: [Int: UserSafetyState] = [:]
  private var generation = UUID()

  var blockedUserIDs: Set<Int> {
    Set(states.compactMap { $0.value.isBlocked ? $0.key : nil })
  }

  func reset() {
    generation = UUID()
    states = [:]
  }

  func load(targetUserID: Int, using account: AccountSession, force: Bool = false) async {
    guard let user = account.user, user.uid != targetUserID, let baseURL = account.apiBaseURL,
      targetUserID > 0, states[targetUserID]?.isLoading != true,
      states[targetUserID]?.isMutating != true,
      force || states[targetUserID]?.isReady != true
    else { return }
    let identity = account.sessionIdentity
    let generation = generation
    var state = states[targetUserID] ?? UserSafetyState()
    state.isLoading = true
    state.error = nil
    states[targetUserID] = state
    do {
      let request = try UserSafetyEndpoint.status(baseURL: baseURL, targetUserID: targetUserID)
      let data = try await account.sendAuthenticated(request)
      let loaded = try JSONDecoder().decode(UserSafetyEndpoint.StatusResponse.self, from: data)
        .checked()
      try Task.checkCancellation()
      guard identity == account.sessionIdentity, generation == self.generation else { return }
      states[targetUserID] = loaded
    } catch is CancellationError {
      guard identity == account.sessionIdentity, generation == self.generation else { return }
      state.isLoading = false
      states[targetUserID] = state
    } catch {
      guard identity == account.sessionIdentity, generation == self.generation else { return }
      state.isLoading = false
      state.error = "신고·차단 상태를 확인하지 못했어요. 다시 시도해 주세요."
      states[targetUserID] = state
    }
  }

  @discardableResult
  func report(
    targetUserID: Int, context: UserReportContext, reason: String,
    using account: AccountSession
  ) async -> Bool {
    guard let user = account.user, user.uid != targetUserID, let baseURL = account.apiBaseURL,
      targetUserID > 0, states[targetUserID]?.isLoading != true,
      states[targetUserID]?.isMutating != true, states[targetUserID]?.isReported != true
    else { return false }
    let identity = account.sessionIdentity
    let generation = generation
    var state = states[targetUserID] ?? UserSafetyState()
    state.isMutating = true
    state.error = nil
    states[targetUserID] = state
    do {
      let request = try UserSafetyEndpoint.report(
        baseURL: baseURL, targetUserID: targetUserID, context: context, reason: reason)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(UserSafetyEndpoint.MutationResponse.self, from: data).check()
      try Task.checkCancellation()
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isReported = true
      state.isReady = true
      state.isMutating = false
      states[targetUserID] = state
      return true
    } catch is CancellationError {
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isMutating = false
      states[targetUserID] = state
      return false
    } catch {
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isMutating = false
      // 응답 유실 시 중복 접수를 막기 위해 다음 조작 전에 서버 상태를 다시 확인한다.
      state.isReady = false
      state.error = "신고를 접수하지 못했어요. 상태를 다시 확인해 주세요."
      states[targetUserID] = state
      return false
    }
  }

  @discardableResult
  func setBlocked(targetUserID: Int, blocked: Bool, using account: AccountSession) async -> Bool {
    guard let user = account.user, user.uid != targetUserID, let baseURL = account.apiBaseURL,
      targetUserID > 0, states[targetUserID]?.isLoading != true,
      states[targetUserID]?.isMutating != true
    else { return false }
    let identity = account.sessionIdentity
    let generation = generation
    var state = states[targetUserID] ?? UserSafetyState()
    state.isMutating = true
    state.error = nil
    states[targetUserID] = state
    do {
      let request = try UserSafetyEndpoint.block(
        baseURL: baseURL, targetUserID: targetUserID, blocked: blocked)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(UserSafetyEndpoint.MutationResponse.self, from: data).check()
      try Task.checkCancellation()
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isBlocked = blocked
      state.isReady = true
      state.isMutating = false
      states[targetUserID] = state
      return true
    } catch is CancellationError {
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isMutating = false
      states[targetUserID] = state
      return false
    } catch {
      guard identity == account.sessionIdentity, generation == self.generation else { return false }
      state.isMutating = false
      // 응답 유실 시 서버 반영 여부가 불명확하므로 서버 상태를 다시 조회한다.
      state.isReady = false
      state.error =
        blocked
        ? "차단하지 못했어요. 상태를 다시 확인해 주세요."
        : "차단을 해제하지 못했어요. 상태를 다시 확인해 주세요."
      states[targetUserID] = state
      return false
    }
  }
}

struct UserReportSheet: View {
  let targetUserID: Int
  let targetName: String
  let context: UserReportContext
  let account: AccountSession
  @State private var reason = ""
  @Environment(\.dismiss) private var dismiss

  private var trimmedReason: String {
    reason.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var state: UserSafetyState? { account.userSafety.states[targetUserID] }
  private var canSubmit: Bool {
    trimmedReason.utf16.count >= 5 && trimmedReason.utf16.count <= 500
      && state?.isMutating != true
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            context == .user
              ? "운영진이 확인할 수 있도록 문제가 된 행동을 구체적으로 적어주세요."
              : "운영진이 확인할 수 있도록 이 사진의 문제를 구체적으로 적어주세요."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)

          TextEditor(text: $reason)
            .frame(minHeight: 150)
            .accessibilityLabel("신고 사유")
            .accessibilityIdentifier("user-report-reason")

          HStack {
            Text("5자 이상 입력해 주세요.")
            Spacer()
            Text("\(trimmedReason.utf16.count)/500")
              .monospacedDigit()
          }
          .font(.caption)
          .foregroundStyle(trimmedReason.utf16.count > 500 ? Color.red : Color.secondary)
        }

        if let error = state?.error {
          Section {
            Label(error, systemImage: "exclamationmark.circle")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(context == .user ? "\(targetName)님 신고" : "사진 신고")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }.disabled(state?.isMutating == true)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("신고 접수") {
            Task {
              if await account.userSafety.report(
                targetUserID: targetUserID, context: context, reason: trimmedReason,
                using: account)
              {
                dismiss()
              }
            }
          }
          .disabled(!canSubmit)
          .accessibilityIdentifier("user-report-submit")
        }
      }
      .interactiveDismissDisabled(state?.isMutating == true)
      .onChange(of: reason) { _, newValue in
        var limited = newValue
        while limited.utf16.count > 500 { limited.removeLast() }
        if limited != newValue { reason = limited }
      }
    }
  }
}
