import Foundation
import Testing

@testable import SENSTA

@MainActor
private final class DirectMessageTokenStore: AccountTokenStoring {
  var tokens: AccountTokens?
  func read() throws -> AccountTokens? { tokens }
  func save(_ tokens: AccountTokens) throws { self.tokens = tokens }
  func clear() throws { tokens = nil }
}

private actor DirectMessageAccountStub: AccountServing {
  enum Mode { case normal, rejectSend, duplicateHistory }
  let mode: Mode
  private(set) var requests: [URLRequest] = []

  init(_ mode: Mode = .normal) { self.mode = mode }

  func data(for request: URLRequest) async throws -> Data {
    requests.append(request)
    switch request.url?.path {
    case "/goapi/chat/list":
      return Data(
        #"{"success":true,"error":"","code":0,"result":[{"sender":{"uid":2,"name":"빛 &amp; 결","profile":"/upload/profile/2.webp"},"uid":11,"message":"오래된 메시지","timestamp":1000},{"sender":{"uid":3,"name":"여백","profile":""},"uid":22,"message":"새 메시지","timestamp":3000}]}"#
          .utf8)
    case "/goapi/chat/history":
      let duplicate = mode == .duplicateHistory ? 101 : 102
      return Data(
        "{\"success\":true,\"error\":\"\",\"code\":0,\"result\":[{\"uid\":\(duplicate),\"userUid\":7,\"message\":\"답장\",\"timestamp\":2000},{\"uid\":101,\"userUid\":2,\"message\":\"안녕 &amp; 반가워요\",\"timestamp\":1000}]}"
          .utf8)
    case "/goapi/chat/save":
      if mode == .rejectSend {
        return Data(#"{"success":false,"error":"blocked","code":4,"result":null}"#.utf8)
      }
      return Data(#"{"success":true,"error":"","code":0,"result":103}"#.utf8)
    default:
      throw NuboAPIError.invalidRequest
    }
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (
      AccountUser(uid: 7, name: "나", id: email, blocked: false),
      AccountTokens(token: "chat-access", refresh: "chat-refresh")
    )
  }
  func load(token: String) async throws -> AccountUser {
    AccountUser(uid: 7, name: "나", id: "me@example.com", blocked: false)
  }
  func refresh(_ refresh: String) async throws -> AccountTokens {
    AccountTokens(token: "chat-access-2", refresh: "chat-refresh-2")
  }
  func logout(token: String) async throws {}
}

struct DirectMessagesTests {
  private let baseURL = URL(string: "https://sensta.me/goapi/")!
  private let partner = DirectMessagePartner(id: 2, name: "빛", profileURL: nil)

  @Test func endpointsMatchAndroidContractWithoutEmbeddingCredentials() throws {
    let list = try DirectMessageEndpoint.threads(baseURL: baseURL, limit: 30)
    #expect(list.url?.path == "/goapi/chat/list")
    #expect(list.url?.query == "limit=30")
    #expect(list.httpMethod == "GET")
    #expect(list.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(list.httpShouldHandleCookies == false)

    let history = try DirectMessageEndpoint.history(
      baseURL: baseURL, targetUserID: 2, limit: 100)
    #expect(history.url?.path == "/goapi/chat/history")
    #expect(history.url?.query == "targetUserUid=2&limit=100")
    #expect(history.httpMethod == "GET")

    let send = try DirectMessageEndpoint.send(
      baseURL: baseURL, targetUserID: 2, message: "  안녕하세요  ")
    #expect(send.url?.path == "/goapi/chat/save")
    #expect(send.httpMethod == "POST")
    #expect(send.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(send.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(
      try JSONDecoder().decode([String: JSONValue].self, from: send.httpBody!) == [
        "targetUserUid": .number(2), "message": .string("안녕하세요"),
      ])
    #expect(throws: NuboAPIError.invalidRequest) {
      try DirectMessageEndpoint.send(baseURL: baseURL, targetUserID: 2, message: "   ")
    }
    #expect(throws: NuboAPIError.invalidRequest) {
      try DirectMessageEndpoint.history(baseURL: baseURL, targetUserID: 0)
    }
  }

  @MainActor @Test func listAndHistoryAreNormalizedSortedAndAuthenticated() async throws {
    let service = DirectMessageAccountStub()
    let session = AccountSession(
      service: service, store: DirectMessageTokenStore(), apiBaseURL: baseURL)
    await session.signin(email: "me@example.com", password: "secret")

    let list = DirectMessageThreadListModel()
    await list.load(using: session)
    #expect(list.threads.map(\.partner.id) == [3, 2])
    #expect(list.threads.last?.partner.name == "빛 & 결")
    #expect(list.threads.last?.partner.profileURL?.path == "/upload/profile/2.webp")

    let chat = DirectMessageModel()
    await chat.load(partner: partner, using: session)
    #expect(chat.messages.map(\.id) == [101, 102])
    #expect(chat.messages.first?.text == "안녕 & 반가워요")

    let requests = await service.requests
    #expect(requests.count == 2)
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer chat-access"
          && $0.httpShouldHandleCookies == false
      })
  }

  @MainActor @Test func successfulSendAppendsMineAndClearsOnlySubmittedDraft() async {
    let service = DirectMessageAccountStub()
    let session = AccountSession(
      service: service, store: DirectMessageTokenStore(), apiBaseURL: baseURL)
    await session.signin(email: "me@example.com", password: "secret")
    let model = DirectMessageModel()
    await model.load(partner: partner, using: session)
    model.draft = "  새 사진 멋져요  "

    await model.send(to: partner, using: session)

    #expect(model.messages.last?.id == 103)
    #expect(model.messages.last?.senderID == 7)
    #expect(model.messages.last?.text == "새 사진 멋져요")
    #expect(model.draft.isEmpty)
    #expect(model.sendError == nil)
    let request = await service.requests.last
    #expect(request?.url?.path == "/goapi/chat/save")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer chat-access")
  }

  @MainActor @Test func rejectedSendAndMalformedHistoryPreserveSafeState() async {
    let rejectedService = DirectMessageAccountStub(.rejectSend)
    let rejectedSession = AccountSession(
      service: rejectedService, store: DirectMessageTokenStore(), apiBaseURL: baseURL)
    await rejectedSession.signin(email: "me@example.com", password: "secret")
    let rejected = DirectMessageModel()
    rejected.draft = "지우면 안 되는 초안"
    await rejected.send(to: partner, using: rejectedSession)
    #expect(rejected.draft == "지우면 안 되는 초안")
    #expect(rejected.messages.isEmpty)
    #expect(rejected.sendError != nil)

    let malformedService = DirectMessageAccountStub(.duplicateHistory)
    let malformedSession = AccountSession(
      service: malformedService, store: DirectMessageTokenStore(), apiBaseURL: baseURL)
    await malformedSession.signin(email: "me@example.com", password: "secret")
    let malformed = DirectMessageModel()
    await malformed.load(partner: partner, using: malformedSession)
    #expect(malformed.messages.isEmpty)
    #expect(malformed.loadError != nil)
  }
}

private enum JSONValue: Decodable, Equatable {
  case string(String)
  case number(Int)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Int.self) {
      self = .number(value)
    } else {
      self = .string(try container.decode(String.self))
    }
  }
}
