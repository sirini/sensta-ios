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

@MainActor
private final class LogoutCoordinatorSpy: AccountLogoutCoordinating {
  private(set) var observedAuthenticatedSession = false

  func prepareForLogout(using account: AccountSession) async {
    observedAuthenticatedSession = account.user != nil
  }
}

private actor AccountStub: AccountServing {
  enum Mode {
    case normal, expired, rejected, offline, paused, appleLinkRequired, appleAudienceMismatch
  }
  let mode: Mode
  var refreshCount = 0
  var signinCount = 0
  var googleSigninCount = 0
  var appleSigninCount = 0
  private var continuation: CheckedContinuation<Void, Never>?
  init(_ mode: Mode = .normal) { self.mode = mode }
  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    signinCount += 1
    if mode == .paused { await withCheckedContinuation { continuation = $0 } }
    return (testUser, testTokens)
  }
  func signinWithGoogle(idToken: String) async throws -> (AccountUser, AccountTokens) {
    googleSigninCount += 1
    return (testUser, testTokens)
  }
  func appleNonce() async throws -> String { "server-apple-nonce" }
  func signinWithApple(identityToken: String, nonce: String, name: String) async throws
    -> (AccountUser, AccountTokens)
  {
    appleSigninCount += 1
    if mode == .appleLinkRequired {
      throw NuboAPIError.server(
        code: 13, message: "sign in to the existing account and link Apple ID")
    }
    if mode == .appleAudienceMismatch {
      throw NuboAPIError.server(code: 2, message: "Apple token audience is not allowed")
    }
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

private actor AppleLinkStub: AccountServing {
  var linked = false
  var authorizationHeaders: [String] = []

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (testUser, testTokens)
  }

  func data(for request: URLRequest) async throws -> Data {
    authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    switch request.url?.path {
    case "/goapi/auth/apple/status":
      return Data(
        "{\"success\":true,\"code\":0,\"result\":{\"linked\":\(linked)}}".utf8)
    case "/goapi/auth/apple/link/nonce":
      return Data(#"{"success":true,"code":0,"result":{"nonce":"bound-link-nonce"}}"#.utf8)
    case "/goapi/auth/apple/link":
      let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
      guard body["identityToken"] == "apple.jwt", body["nonce"] == "bound-link-nonce" else {
        throw NuboAPIError.invalidRequest
      }
      linked = true
      return Data(#"{"success":true,"code":0,"result":{"linked":true}}"#.utf8)
    default:
      throw NuboAPIError.invalidRequest
    }
  }

  func load(token: String) async throws -> AccountUser { testUser }
  func refresh(_ refresh: String) async throws -> AccountTokens { rotatedTokens }
  func logout(token: String) async throws {}
}

private actor AccountDeletionStub: AccountServing {
  let appleLinked: Bool
  let rejectsDeletion: Bool
  private(set) var authorizationHeaders: [String] = []
  private(set) var deletionBody: [String: String] = [:]

  init(appleLinked: Bool, rejectsDeletion: Bool = false) {
    self.appleLinked = appleLinked
    self.rejectsDeletion = rejectsDeletion
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (testUser, testTokens)
  }

  func data(for request: URLRequest) async throws -> Data {
    authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    switch request.url?.path {
    case "/goapi/auth/apple/status":
      return Data(
        "{\"success\":true,\"code\":0,\"result\":{\"linked\":\(appleLinked)}}".utf8)
    case "/goapi/auth/apple/delete/nonce":
      return Data(
        #"{"success":true,"code":0,"result":{"nonce":"delete-nonce"}}"#.utf8)
    case "/goapi/auth/account", "/goapi/auth/apple/account":
      deletionBody = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
      if rejectsDeletion {
        return Data(#"{"success":false,"code":4,"error":"server detail","result":null}"#.utf8)
      }
      return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
    default:
      throw NuboAPIError.invalidRequest
    }
  }

  func load(token: String) async throws -> AccountUser { testUser }
  func refresh(_ refresh: String) async throws -> AccountTokens { rotatedTokens }
  func logout(token: String) async throws {}
}

private actor UploadAccountStub: AccountServing {
  private(set) var authorizationHeaders: [String] = []
  private(set) var uploadedBodies: [Data] = []

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (testUser, testTokens)
  }
  func load(token: String) async throws -> AccountUser { testUser }
  func refresh(_ refresh: String) async throws -> AccountTokens { rotatedTokens }
  func logout(token: String) async throws {}

  func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> Data {
    authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    uploadedBodies.append(try Data(contentsOf: fileURL))
    if authorizationHeaders.count == 1 { throw NuboAPIError.httpStatus(401) }
    return Data(#"{"success":true,"code":0,"result":101}"#.utf8)
  }
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

  @Test func signupAndVerificationUseTheExistingAndroidFormContract() throws {
    let baseURL = URL(string: "https://example.com/goapi/")!
    let signup = try AccountEndpoint.signup(
      baseURL: baseURL, email: " photo+ios@example.com ", password: "Password!+1",
      name: " 사진가 ", invite: " invite+code ")
    #expect(signup.url?.path == "/goapi/auth/signup")
    #expect(signup.httpMethod == "POST")
    #expect(signup.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(signup.httpShouldHandleCookies == false)
    #expect(
      String(decoding: signup.httpBody!, as: UTF8.self)
        == "id=photo%2Bios%40example.com&password=Password%21%2B1&name=%EC%82%AC%EC%A7%84%EA%B0%80&invite=invite%2Bcode"
    )

    let verify = try AccountEndpoint.verifySignup(
      baseURL: baseURL, target: 42, code: "123456", email: "photo+ios@example.com",
      password: "Password!+1", name: "사진가")
    #expect(verify.url?.path == "/goapi/auth/verify")
    #expect(
      String(decoding: verify.httpBody!, as: UTF8.self)
        == "target=42&code=123456&id=photo%2Bios%40example.com&password=Password%21%2B1&name=%EC%82%AC%EC%A7%84%EA%B0%80"
    )
  }

  @Test func accountDeletionContractsRequireExactConfirmationAndFreshAppleAuthorization() throws {
    let baseURL = URL(string: "https://example.com/goapi/")!
    let standard = try AccountEndpoint.deleteAccount(baseURL: baseURL, confirmation: "DELETE")
    #expect(standard.url?.path == "/goapi/auth/account")
    #expect(standard.httpMethod == "DELETE")
    #expect(
      try JSONDecoder().decode([String: String].self, from: standard.httpBody!) == [
        "confirmation": "DELETE"
      ])

    let apple = try AccountEndpoint.deleteAppleAccount(
      baseURL: baseURL, identityToken: "apple.identity", authorizationCode: "fresh.code",
      nonce: "delete.nonce", confirmation: "DELETE")
    #expect(apple.url?.path == "/goapi/auth/apple/account")
    #expect(apple.httpMethod == "DELETE")
    #expect(
      try JSONDecoder().decode([String: String].self, from: apple.httpBody!) == [
        "identityToken": "apple.identity", "authorizationCode": "fresh.code",
        "nonce": "delete.nonce", "confirmation": "DELETE",
      ])
    #expect(throws: NuboAPIError.invalidRequest) {
      try AccountEndpoint.deleteAccount(baseURL: baseURL, confirmation: "delete")
    }
    #expect(throws: NuboAPIError.invalidRequest) {
      try AccountEndpoint.deleteAppleAccount(
        baseURL: baseURL, identityToken: "apple.identity", authorizationCode: "",
        nonce: "delete.nonce", confirmation: "DELETE")
    }
  }

  @Test func passwordResetUsesPublicJSONContractWithoutLeakingCredentials() throws {
    let request = try AccountEndpoint.resetPassword(
      baseURL: URL(string: "https://example.com/goapi/")!,
      email: " photo+ios@example.com \n")
    #expect(request.url?.path == "/goapi/auth/reset-password")
    #expect(request.httpMethod == "POST")
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(
      try JSONDecoder().decode([String: String].self, from: request.httpBody!) == [
        "email": "photo+ios@example.com"
      ])
    #expect(throws: NuboAPIError.invalidRequest) {
      try AccountEndpoint.resetPassword(
        baseURL: URL(string: "https://example.com/goapi/")!, email: "  \n")
    }
  }

  @Test func decodesSignupPolicyAndVerificationResult() throws {
    let status = try JSONDecoder().decode(
      AccountEnvelope<SignupStatus>.self,
      from: Data(
        #"{"success":true,"code":0,"result":{"mode":"verified_email","mailConfigured":true,"oauthRegistrationAllowed":true}}"#
          .utf8)
    ).checked()
    #expect(status.mode == "verified_email")
    #expect(status.mailConfigured)
    let result = try JSONDecoder().decode(
      AccountEnvelope<SignupResult>.self,
      from: Data(
        #"{"success":true,"code":0,"result":{"target":42,"requiresVerification":true,"completed":false}}"#
          .utf8)
    ).checked()
    #expect(result == SignupResult(target: 42, requiresVerification: true, completed: false))
  }

  @Test func signupValidationMatchesServerPasswordRules() {
    #expect(EmailSignupValidator.emailIsValid("photo+ios@example.com"))
    #expect(!EmailSignupValidator.emailIsValid("photo@localhost"))
    #expect(EmailSignupValidator.passwordIsValid("Password!1"))
    #expect(!EmailSignupValidator.passwordIsValid("password!"))
    #expect(!EmailSignupValidator.passwordIsValid("Password1"))
    #expect(!EmailSignupValidator.passwordIsValid("Pass word!1"))
    #expect(
      EmailSignupValidator.message(
        email: "photo@example.com", name: "사진가", password: "Password!1",
        confirmation: "Password!1", accepted: true) == nil)
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

  @Test func googleSigninUsesSharedAndroidContractAndNoCookies() throws {
    let request = try AccountEndpoint.googleSignin(
      baseURL: URL(string: "https://example.com/goapi/")!, idToken: "header.payload+signature")
    #expect(request.url?.path == "/goapi/auth/android/google")
    #expect(request.httpMethod == "POST")
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(
      request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    #expect(
      String(decoding: request.httpBody!, as: UTF8.self) == "id_token=header.payload%2Bsignature")
  }

  @Test func appleSigninUsesServerNonceAndJSONWithoutAuthorization() throws {
    let request = try AccountEndpoint.appleSignin(
      baseURL: URL(string: "https://example.com/goapi/")!, identityToken: "apple.jwt",
      nonce: "server-nonce", name: "사진가")
    #expect(request.url?.path == "/goapi/auth/apple")
    #expect(request.httpMethod == "POST")
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
    #expect(body == ["identityToken": "apple.jwt", "nonce": "server-nonce", "name": "사진가"])

    let link = try AccountEndpoint.appleLink(
      baseURL: URL(string: "https://example.com/goapi/")!, identityToken: "apple.jwt",
      nonce: "link-nonce", name: "")
    #expect(link.url?.path == "/goapi/auth/apple/link")
    #expect(link.value(forHTTPHeaderField: "Authorization") == nil)
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
    #expect(throws: NuboAPIError.server(code: 4, message: "internal detail")) {
      try JSONDecoder().decode(AccountEnvelope<AccountSigninResult>.self, from: failure)
        .checked(includeServerMessage: true)
    }
  }
}

private actor AchievementAccountStub: AccountServing {
  let rejectsAcknowledgement: Bool
  let returnsDuplicate: Bool
  private(set) var methods: [String] = []
  private(set) var authorizationHeaders: [String] = []
  private(set) var acknowledgedKeys: [String] = []

  init(rejectsAcknowledgement: Bool = false, returnsDuplicate: Bool = false) {
    self.rejectsAcknowledgement = rejectsAcknowledgement
    self.returnsDuplicate = returnsDuplicate
  }

  func data(for request: URLRequest) async throws -> Data {
    methods.append(request.httpMethod ?? "")
    authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    if request.httpMethod == "PATCH" {
      let body = try JSONDecoder().decode([String: [String]].self, from: request.httpBody!)
      acknowledgedKeys.append(contentsOf: body["keys"] ?? [])
      if rejectsAcknowledgement {
        return Data(#"{"success":false,"code":4,"error":"internal","result":null}"#.utf8)
      }
      return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
    }
    let first =
      #"{"key":"sensta-app","name":"SENSTA 앱 포토그래퍼","description":"앱으로 사진을 공유했습니다.","iconKey":"aperture","earnedAt":1788410731496}"#
    let second =
      returnsDuplicate
      ? first
      : #"{"key":"first-post","name":"첫 발자국","description":"첫 게시글을 작성했습니다.","iconKey":"notebook-pen","earnedAt":1788410731497}"#
    return Data("{\"success\":true,\"code\":0,\"error\":\"\",\"result\":[\(first),\(second)]}".utf8)
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (testUser, testTokens)
  }
  func load(token: String) async throws -> AccountUser { testUser }
  func refresh(_ refresh: String) async throws -> AccountTokens { rotatedTokens }
  func logout(token: String) async throws {}
}

struct AchievementTests {
  private let baseURL = URL(string: "https://example.com/goapi/")!

  @Test func endpointUsesAuthenticatedJSONContractWithoutEmbeddingCredentials() throws {
    let pending = try AccountEndpoint.pendingAchievements(baseURL: baseURL)
    #expect(pending.url?.path == "/goapi/auth/user/achievements")
    #expect(pending.httpMethod == "GET")
    #expect(pending.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(pending.httpShouldHandleCookies == false)

    let acknowledgement = try AccountEndpoint.acknowledgeAchievements(
      baseURL: baseURL, keys: [" sensta-app "])
    #expect(acknowledgement.httpMethod == "PATCH")
    #expect(acknowledgement.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(acknowledgement.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(
      try JSONDecoder().decode([String: [String]].self, from: acknowledgement.httpBody!) == [
        "keys": ["sensta-app"]
      ])
    #expect(throws: NuboAPIError.invalidRequest) {
      try AccountEndpoint.acknowledgeAchievements(baseURL: baseURL, keys: [])
    }
    #expect(throws: NuboAPIError.invalidRequest) {
      try AccountEndpoint.acknowledgeAchievements(baseURL: baseURL, keys: ["same", "same"])
    }
  }

  @MainActor @Test func inboxChecksAndAcknowledgesOneBadgeAtATime() async {
    let service = AchievementAccountStub()
    let session = AccountSession(
      service: service, store: MemoryTokenStore(), apiBaseURL: baseURL)
    await session.signin(email: "photo@example.com", password: "secret")

    await session.achievements.check(using: session)
    #expect(session.achievements.badges.map(\.key) == ["sensta-app", "first-post"])
    #expect(await session.achievements.acknowledgeCurrent(using: session))
    #expect(session.achievements.current?.key == "first-post")
    #expect(await service.methods == ["GET", "PATCH"])
    #expect(await service.authorizationHeaders == ["Bearer access-one", "Bearer access-one"])
    #expect(await service.acknowledgedKeys == ["sensta-app"])
  }

  @MainActor @Test func malformedDuplicateBadgesAreRejectedAndLogoutClearsQueue() async {
    let malformedService = AchievementAccountStub(returnsDuplicate: true)
    let malformedSession = AccountSession(
      service: malformedService, store: MemoryTokenStore(), apiBaseURL: baseURL)
    await malformedSession.signin(email: "photo@example.com", password: "secret")
    await malformedSession.achievements.check(using: malformedSession)
    #expect(malformedSession.achievements.badges.isEmpty)

    let service = AchievementAccountStub()
    let session = AccountSession(
      service: service, store: MemoryTokenStore(), apiBaseURL: baseURL)
    await session.signin(email: "photo@example.com", password: "secret")
    await session.achievements.check(using: session)
    #expect(!session.achievements.badges.isEmpty)
    await session.logout()
    #expect(session.achievements.badges.isEmpty)
  }

  @MainActor @Test func failedAcknowledgementPreservesBadgeUntilUserSnoozesIt() async {
    let service = AchievementAccountStub(rejectsAcknowledgement: true)
    let session = AccountSession(
      service: service, store: MemoryTokenStore(), apiBaseURL: baseURL)
    await session.signin(email: "photo@example.com", password: "secret")
    await session.achievements.check(using: session)

    #expect(await session.achievements.acknowledgeCurrent(using: session) == false)
    #expect(session.achievements.current?.key == "sensta-app")
    #expect(session.achievements.acknowledgementMessage != nil)
    session.achievements.snoozeCurrent()
    #expect(session.achievements.current?.key == "first-post")
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

  @Test func googleSigninPersistsTheSameMobileSessionPair() async {
    let service = AccountStub()
    let store = MemoryTokenStore()
    let session = AccountSession(service: service, store: store)
    await session.signinWithGoogle(idToken: "google-id-token")
    #expect(await service.googleSigninCount == 1)
    #expect(store.value == testTokens)
    #expect(session.user == testUser)
    #expect(!session.needsRestoration)
  }

  @Test func appleSigninPersistsPairAndMarksProviderLinked() async {
    let service = AccountStub()
    let store = MemoryTokenStore()
    let session = AccountSession(service: service, store: store)
    await session.signinWithApple(
      identityToken: "apple-id-token", nonce: "server-apple-nonce", name: "사진가")
    #expect(await service.appleSigninCount == 1)
    #expect(store.value == testTokens)
    #expect(session.user == testUser)
    #expect(session.appleLinked == true)
  }

  @Test func appleSigninDoesNotAutoMergeAnExistingEmailAccount() async {
    let store = MemoryTokenStore()
    let session = AccountSession(service: AccountStub(.appleLinkRequired), store: store)
    await session.signinWithApple(
      identityToken: "apple-id-token", nonce: "server-apple-nonce", name: "사진가")
    #expect(store.value == nil)
    #expect(session.user == nil)
    #expect(session.error?.contains("로그인한 뒤") == true)
  }

  @Test func appleSigninExplainsAnAudienceConfigurationMismatch() async {
    let session = AccountSession(
      service: AccountStub(.appleAudienceMismatch), store: MemoryTokenStore())
    await session.signinWithApple(
      identityToken: "apple-id-token", nonce: "server-apple-nonce", name: "사진가")
    #expect(session.user == nil)
    #expect(session.error?.contains("앱 식별자") == true)
  }

  @Test func existingSessionExplicitlyLinksAppleWithAuthenticatedNonce() async {
    let service = AppleLinkStub()
    let session = AccountSession(
      service: service, store: MemoryTokenStore(),
      apiBaseURL: URL(string: "https://example.com/goapi/")!)
    await session.signin(email: testUser.id, password: "secret")
    await session.loadAppleStatus()
    #expect(session.appleLinked == false)
    let nonce = await session.prepareAppleAuthorization(linking: true)
    #expect(nonce == "bound-link-nonce")
    await session.linkApple(identityToken: "apple.jwt", nonce: nonce!, name: "")
    #expect(session.appleLinked == true)
    #expect(
      await service.authorizationHeaders == [
        "Bearer access-one", "Bearer access-one", "Bearer access-one",
      ])
  }

  @Test func standardAccountDeletionClearsSessionOnlyAfterServerSuccess() async {
    let service = AccountDeletionStub(appleLinked: false)
    let store = MemoryTokenStore()
    let session = AccountSession(
      service: service, store: store, apiBaseURL: URL(string: "https://example.com/goapi/")!)
    await session.signin(email: testUser.id, password: "secret")
    await session.loadAppleStatus()

    #expect(await session.deleteAccount(confirmation: "DELETE"))
    #expect(session.user == nil)
    #expect(store.value == nil)
    #expect(await service.deletionBody == ["confirmation": "DELETE"])
    #expect(await service.authorizationHeaders.allSatisfy { $0 == "Bearer access-one" })
  }

  @Test func appleAccountDeletionUsesBoundNonceAndAuthorizationCode() async {
    let service = AccountDeletionStub(appleLinked: true)
    let store = MemoryTokenStore()
    let session = AccountSession(
      service: service, store: store, apiBaseURL: URL(string: "https://example.com/goapi/")!)
    await session.signin(email: testUser.id, password: "secret")
    await session.loadAppleStatus()
    let nonce = await session.prepareAppleAccountDeletion()

    #expect(nonce == "delete-nonce")
    #expect(
      await session.deleteAppleAccount(
        identityToken: "apple.identity", authorizationCode: "fresh.code",
        nonce: nonce!, confirmation: "DELETE"))
    #expect(session.user == nil)
    #expect(store.value == nil)
    #expect(
      await service.deletionBody == [
        "identityToken": "apple.identity", "authorizationCode": "fresh.code",
        "nonce": "delete-nonce", "confirmation": "DELETE",
      ])
  }

  @Test func rejectedAccountDeletionPreservesLocalSession() async {
    let service = AccountDeletionStub(appleLinked: false, rejectsDeletion: true)
    let store = MemoryTokenStore()
    let session = AccountSession(
      service: service, store: store, apiBaseURL: URL(string: "https://example.com/goapi/")!)
    await session.signin(email: testUser.id, password: "secret")

    #expect(await session.deleteAccount(confirmation: "DELETE") == false)
    #expect(session.user == testUser)
    #expect(store.value == testTokens)
    #expect(session.error?.contains("그대로 유지") == true)
  }

  @Test func googleButtonRequiresBothClientIDs() {
    #expect(!GoogleSignInClient(info: [:]).isAvailable)
    #expect(
      !GoogleSignInClient(info: ["GIDClientID": "ios.apps.googleusercontent.com"]).isAvailable)
    #expect(
      GoogleSignInClient(info: [
        "GIDClientID": "ios.apps.googleusercontent.com",
        "GIDServerClientID": "server.apps.googleusercontent.com",
      ]).isAvailable)
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

  @Test func logoutUnregistersPushBeforeClearingSession() async {
    let session = AccountSession(service: AccountStub(), store: MemoryTokenStore(testTokens))
    await session.restore()
    let coordinator = LogoutCoordinatorSpy()
    session.logoutCoordinator = coordinator

    await session.logout()

    #expect(coordinator.observedAuthenticatedSession)
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
  @Test func authenticatedFileUploadRotatesAndRetriesTheSameBody() async throws {
    let baseURL = URL(string: "https://example.com/goapi/")!
    let service = UploadAccountStub()
    let store = MemoryTokenStore(testTokens)
    let session = AccountSession(service: service, store: store, apiBaseURL: baseURL)
    await session.restore()
    let fileURL = FileManager.default.temporaryDirectory
      .appending(path: "account-upload-\(UUID().uuidString)")
    let body = Data("same-upload-body".utf8)
    try body.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    var request = URLRequest(url: baseURL.appending(path: "editor/write"))
    request.httpMethod = "POST"

    let response = try await session.uploadAuthenticated(request, fromFile: fileURL)

    #expect(String(decoding: response, as: UTF8.self).contains("101"))
    #expect(
      await service.authorizationHeaders == ["Bearer access-one", "Bearer access-two"])
    #expect(await service.uploadedBodies == [body, body])
    #expect(store.value == rotatedTokens)
  }

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
