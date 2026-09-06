import Foundation
import Testing

@testable import SENSTA

private let safetyBaseURL = URL(string: "https://example.com/goapi/")!
private final class SafetyFixtureMarker {}

@MainActor private final class SafetyTokenStore: AccountTokenStoring {
  var value: AccountTokens? = AccountTokens(token: "safety-access", refresh: "safety-refresh")
  func read() throws -> AccountTokens? { value }
  func save(_ tokens: AccountTokens) throws { value = tokens }
  func clear() throws { value = nil }
}

private actor SafetyServiceStub: AccountServing {
  enum Mode { case normal, uncertainMutation }
  let mode: Mode
  private(set) var requests: [URLRequest] = []
  private var reported = false
  private var blocked = false

  init(_ mode: Mode = .normal) { self.mode = mode }

  func data(for request: URLRequest) async throws -> Data {
    requests.append(request)
    if request.url?.path == "/goapi/board/list" {
      guard request.value(forHTTPHeaderField: "Authorization") == "Bearer safety-access" else {
        throw NuboAPIError.httpStatus(401)
      }
      let url = Bundle(for: SafetyFixtureMarker.self).url(
        forResource: "board-list-photo", withExtension: "json")!
      return try Data(contentsOf: url)
    }
    switch (request.url?.path, request.httpMethod) {
    case ("/goapi/auth/user/report", "GET"):
      return Data(
        "{\"success\":true,\"code\":0,\"error\":\"\",\"result\":{\"isReported\":\(reported),\"isBannedByMe\":\(blocked)}}"
          .utf8)
    case ("/goapi/auth/user/report", "POST"):
      if mode == .uncertainMutation { throw NuboAPIError.networkFailure }
      reported = true
      return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
    case ("/goapi/auth/user/block", "PUT"):
      if mode == .uncertainMutation { throw NuboAPIError.networkFailure }
      blocked = true
      return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
    case ("/goapi/auth/user/block", "DELETE"):
      blocked = false
      return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
    default:
      throw NuboAPIError.invalidRequest
    }
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (try await load(token: ""), AccountTokens(token: "safety-access", refresh: "safety-refresh"))
  }
  func load(token: String) async throws -> AccountUser {
    AccountUser(uid: 7, name: "나", id: "me@example.com", blocked: false)
  }
  func refresh(_ refresh: String) async throws -> AccountTokens {
    AccountTokens(token: "safety-access-2", refresh: "safety-refresh-2")
  }
  func logout(token: String) async throws {}
}

@MainActor struct UserSafetyTests {
  private func setup(_ service: SafetyServiceStub = SafetyServiceStub()) async -> AccountSession {
    let session = AccountSession(
      service: service, store: SafetyTokenStore(), apiBaseURL: safetyBaseURL)
    await session.restore()
    return session
  }

  @Test func endpointsMatchAndroidContract() throws {
    let status = try UserSafetyEndpoint.status(baseURL: safetyBaseURL, targetUserID: 42)
    #expect(status.url?.path == "/goapi/auth/user/report")
    #expect(status.url?.query == "targetUserUid=42")
    #expect(status.httpMethod == "GET")

    let report = try UserSafetyEndpoint.report(
      baseURL: safetyBaseURL, targetUserID: 42, context: .photo(postID: 101),
      reason: "  부적절한 사진입니다  ")
    let reportBody = try JSONSerialization.jsonObject(with: report.httpBody!) as! [String: Any]
    #expect(report.httpMethod == "POST")
    #expect(reportBody["targetUserUid"] as? Int == 42)
    #expect(reportBody["checkedBlackList"] as? Bool == false)
    #expect(reportBody["content"] as? String == "사진 #101 신고: 부적절한 사진입니다")

    let block = try UserSafetyEndpoint.block(
      baseURL: safetyBaseURL, targetUserID: 42, blocked: true)
    let unblock = try UserSafetyEndpoint.block(
      baseURL: safetyBaseURL, targetUserID: 42, blocked: false)
    #expect(block.httpMethod == "PUT")
    #expect(unblock.httpMethod == "DELETE")
    #expect(
      (try JSONSerialization.jsonObject(with: block.httpBody!) as? [String: Int])
        == ["targetUserUid": 42])
  }

  @Test func reportReasonUsesAndroidUTF16Limits() throws {
    #expect(throws: NuboAPIError.invalidRequest) {
      try UserReportContext.user.content(reason: "네 글자")
    }
    #expect(try UserReportContext.user.content(reason: "충분한 사유") == "사용자 신고: 충분한 사유")
    #expect(throws: NuboAPIError.invalidRequest) {
      try UserReportContext.user.content(reason: String(repeating: "가", count: 501))
    }
  }

  @Test func loadsReportsBlocksAndUnblocks() async {
    let account = await setup()
    await account.userSafety.load(targetUserID: 42, using: account)
    #expect(account.userSafety.states[42]?.isReady == true)
    #expect(account.userSafety.states[42]?.isReported == false)
    #expect(account.userSafety.states[42]?.isBlocked == false)

    #expect(
      await account.userSafety.report(
        targetUserID: 42, context: .user, reason: "구체적인 신고 사유", using: account))
    #expect(account.userSafety.states[42]?.isReported == true)
    #expect(await account.userSafety.setBlocked(targetUserID: 42, blocked: true, using: account))
    #expect(account.userSafety.blockedUserIDs == [42])
    #expect(await account.userSafety.setBlocked(targetUserID: 42, blocked: false, using: account))
    #expect(account.userSafety.blockedUserIDs.isEmpty)
  }

  @Test func uncertainMutationRequiresStatusReload() async {
    let service = SafetyServiceStub(.uncertainMutation)
    let account = await setup(service)
    await account.userSafety.load(targetUserID: 42, using: account)
    #expect(
      await account.userSafety.setBlocked(targetUserID: 42, blocked: true, using: account)
        == false)
    #expect(account.userSafety.states[42]?.isReady == false)
    #expect(account.userSafety.states[42]?.error != nil)
  }

  @Test func authenticatedFeedAppliesServerBlacklist() async throws {
    let service = SafetyServiceStub()
    let account = await setup(service)
    let feed = AccountPhotoFeedService(
      fallback: UnavailablePhotoFeedService(), account: account)
    let page = try await feed.fetchPage(1)
    #expect(page.posts.map(\.writer.id) == [42])
    #expect(await service.requests.last?.value(forHTTPHeaderField: "Authorization") != nil)
  }

  @Test func logoutClearsSafetyState() async {
    let account = await setup()
    await account.userSafety.load(targetUserID: 42, using: account)
    await account.userSafety.setBlocked(targetUserID: 42, blocked: true, using: account)
    await account.logout()
    #expect(account.userSafety.states.isEmpty)
  }
}
