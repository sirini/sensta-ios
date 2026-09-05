import Foundation
import Testing

@testable import SENSTA

private let testTokens = AccountTokens(token: "access-one", refresh: "refresh-one")
private let rotatedTokens = AccountTokens(token: "access-two", refresh: "refresh-two")
private let testUser = AccountUser(
  uid: 7, name: "사진가", id: "photo@example.com", blocked: false, profile: "/upload/profile/7.webp")

@MainActor
private final class MemoryTokenStore: AccountTokenStoring {
  var value: AccountTokens?
  var failSave = false
  var failClear = false
  init(_ value: AccountTokens? = nil) { self.value = value }
  func read() throws -> AccountTokens? { value }
  func save(_ tokens: AccountTokens) throws {
    if failSave { throw AccountStorageError.unavailable }
    value = tokens
  }
  func clear() throws {
    if failClear { throw AccountStorageError.unavailable }
    value = nil
  }
}

private actor AccountStub: AccountServing {
  enum Mode { case normal, expired, rejected, offline, paused }
  let mode: Mode
  var refreshCount = 0
  var signinCount = 0
  private var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .normal) { self.mode = mode }
  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    signinCount += 1
    if mode == .paused { await withCheckedContinuation { continuation = $0 } }
    return (testUser, testTokens)
  }
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func load(token: String) async throws -> AccountUser {
    if mode == .offline { throw NuboAPIError.networkUnavailable }
    if token == testTokens.token && (mode == .expired || mode == .rejected) {
      throw NuboAPIError.httpStatus(401)
    }
    return testUser
  }
  func refresh(_ refresh: String) async throws -> AccountTokens {
    refreshCount += 1
    if mode == .rejected { throw NuboAPIError.server(code: 4, message: "private server error") }
    return rotatedTokens
  }
  func logout(token: String) async throws {}
}

struct AccountContractTests {
  @Test func formPreservesUnicodeAndPasswordWhitespace() throws {
    let request = try AccountEndpoint.signin(
      baseURL: URL(string: "https://example.com/goapi/")!, email: " photo+ios@example.com \n",
      password: " 비밀 +&%= ")
    #expect(request.url?.path == "/goapi/auth/signin")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.httpShouldHandleCookies == false)
    #expect(
      request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let form = String(decoding: request.httpBody!, as: UTF8.self)
    #expect(form == "id=photo%2Bios%40example.com&password=%20%EB%B9%84%EB%B0%80%20%2B%26%25%3D%20")
  }

  @Test func refreshUsesAndroidJSONContractAndNoCookies() throws {
    let request = try AccountEndpoint.refresh(
      baseURL: URL(string: "https://example.com/goapi/")!, refresh: "token+&")
    #expect(request.url?.path == "/goapi/auth/android/refresh")
    #expect(request.httpMethod == "POST")
    #expect(request.httpShouldHandleCookies == false)
    #expect(
      try JSONDecoder().decode([String: String].self, from: request.httpBody!) == [
        "refresh": "token+&"
      ])
    let load = try AccountEndpoint.request(
      baseURL: URL(string: "https://example.com/goapi/")!, path: "auth/load", token: "access")
    #expect(load.value(forHTTPHeaderField: "Authorization") == "Bearer access")
  }

  @Test func rejectsInsecureBaseAndEmptyTokens() {
    #expect(throws: NuboAPIError.configuration) {
      try AccountEndpoint.signin(
        baseURL: URL(string: "http://example.com")!, email: "a@b.com", password: "secret")
    }
    #expect(throws: NuboAPIError.malformedResponse) {
      try AccountTokens(token: "", refresh: "x").checked()
    }
  }

  @Test func decodesAndroidSigninAndRejectsErrorEnvelope() throws {
    let data = Data(
      #"{"success":true,"code":0,"error":"","result":{"uid":7,"name":"사진가","id":"photo@example.com","blocked":false,"token":"access-one","refresh":"refresh-one","profile":"/upload/profile/7.webp","admin":false,"level":2,"signup":123}}"#
        .utf8)
    let result = try JSONDecoder().decode(AccountEnvelope<AccountSigninResult>.self, from: data)
      .checked()
    #expect(result.uid == 7)
    #expect(result.profile == "/upload/profile/7.webp")
    #expect(result.refresh == testTokens.refresh)
    let failure = Data(#"{"success":false,"code":4,"error":"internal detail","result":null}"#.utf8)
    #expect(throws: NuboAPIError.server(code: 4, message: "")) {
      try JSONDecoder().decode(AccountEnvelope<AccountSigninResult>.self, from: failure).checked()
    }
  }
}

@MainActor
struct AccountSessionTests {
  @Test func signinPersistsPairBeforePublishingUser() async {
    let store = MemoryTokenStore()
    let session = AccountSession(
      service: AccountStub(), store: store, apiBaseURL: URL(string: "https://example.com/goapi/")!)
    await session.signin(email: testUser.id, password: "secret")
    #expect(store.value == testTokens)
    #expect(session.profileURL?.absoluteString == "https://example.com/upload/profile/7.webp")
    #expect(session.user == testUser)
    #expect(!session.needsRestoration)
  }

  @Test func failedKeychainSaveDoesNotPublishLogin() async {
    let store = MemoryTokenStore()
    store.failSave = true
    let session = AccountSession(service: AccountStub(), store: store)
    await session.signin(email: testUser.id, password: "secret")
    #expect(session.user == nil)
    #expect(session.error != nil)
  }

  @Test func restoresWithoutUnnecessaryRotation() async {
    let service = AccountStub()
    let session = AccountSession(service: service, store: MemoryTokenStore(testTokens))
    await session.restore()
    #expect(session.user == testUser)
    #expect(await service.refreshCount == 0)
  }

  @Test func rotatesAndPersistsBothTokens() async {
    let store = MemoryTokenStore(testTokens)
    let service = AccountStub(.expired)
    let session = AccountSession(service: service, store: store)
    await session.restore()
    await session.restore()
    #expect(store.value == rotatedTokens)
    #expect(session.user == testUser)
    #expect(await service.refreshCount == 1)
  }

  @Test func rejectedRefreshClearsSession() async {
    let store = MemoryTokenStore(testTokens)
    let session = AccountSession(service: AccountStub(.rejected), store: store)
    await session.restore()
    #expect(store.value == nil)
    #expect(session.user == nil)
    #expect(!session.needsRestoration)
    #expect(session.error != nil)
  }

  @Test func transientFailureKeepsSavedSessionForRetry() async {
    let store = MemoryTokenStore(testTokens)
    let session = AccountSession(service: AccountStub(.offline), store: store)
    await session.restore()
    #expect(store.value == testTokens)
    #expect(session.user == nil)
    #expect(session.needsRestoration)
  }

  @Test func logoutClearsKeychainAndUser() async {
    let store = MemoryTokenStore(testTokens)
    let session = AccountSession(service: AccountStub(), store: store)
    await session.restore()
    await session.logout()
    #expect(store.value == nil)
    #expect(session.user == nil)
  }

  @Test func failedDeletionDoesNotClaimLogout() async {
    let store = MemoryTokenStore(testTokens)
    let session = AccountSession(service: AccountStub(), store: store)
    await session.restore()
    store.failClear = true
    await session.logout()
    #expect(session.user == testUser)
    #expect(session.error != nil)
  }

  @Test func duplicateSigninIsIgnored() async {
    let service = AccountStub(.paused)
    let session = AccountSession(service: service, store: MemoryTokenStore())
    let first = Task { await session.signin(email: "photo@example.com", password: "secret") }
    while await service.signinCount == 0 { await Task.yield() }
    await session.signin(email: "photo@example.com", password: "secret")
    #expect(await service.signinCount == 1)
    await service.resume()
    await first.value
  }
}

private final class BlockedAccountProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let data = Data(
      #"{"success":true,"code":0,"error":"","result":{"uid":7,"name":"blocked","id":"photo@example.com","blocked":true,"token":"access","refresh":"refresh"}}"#
        .utf8)
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

extension AccountContractTests {
  @Test func blockedSigninAndRestorationAreRejected() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BlockedAccountProtocol.self]
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    let service = AccountService(
      baseURL: URL(string: "https://example.com/goapi/")!, session: transport)
    await #expect(throws: NuboAPIError.invalidResponse) {
      try await service.signin(email: "photo@example.com", password: "test")
    }
    await #expect(throws: NuboAPIError.httpStatus(401)) { try await service.load(token: "access") }
  }
}

extension AccountSessionTests {
  @Test func keychainRoundTripReplacesPairAndDeletes() throws {
    let store = KeychainAccountStore(service: "me.sensta.tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    #expect(try store.read() == nil)
    try store.save(testTokens)
    #expect(try store.read() == testTokens)
    try store.save(rotatedTokens)
    #expect(try store.read() == rotatedTokens)
    try store.clear()
    #expect(try store.read() == nil)
  }

  @Test func cancelledSigninDoesNotPersistLateResponse() async {
    let service = AccountStub(.paused)
    let store = MemoryTokenStore()
    let session = AccountSession(service: service, store: store)
    let task = Task { await session.signin(email: "photo@example.com", password: "secret") }
    while await service.signinCount == 0 { await Task.yield() }
    task.cancel()
    await service.resume()
    await task.value
    #expect(store.value == nil)
    #expect(session.user == nil)
    #expect(!session.isBusy)
  }
}
