import Foundation
import Observation
import Security

struct AccountUser: Codable, Equatable, Sendable {
  let uid: Int
  let name: String
  let id: String
  let blocked: Bool
  var profile: String? = nil
}

struct AccountTokens: Codable, Equatable, Sendable {
  let token: String
  let refresh: String

  func checked() throws -> Self {
    guard !token.isEmpty, !refresh.isEmpty else { throw NuboAPIError.malformedResponse }
    return self
  }
}

struct AccountEnvelope<Result: Decodable>: Decodable {
  let success: Bool
  let code: Int
  let result: Result?

  func checked() throws -> Result {
    // 서버의 내부 오류 문자열이나 토큰을 사용자 화면에 노출하지 않는다.
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    guard let result else { throw NuboAPIError.malformedResponse }
    return result
  }
}

struct AccountSigninResult: Decodable {
  let uid: Int
  let name: String
  let id: String
  let blocked: Bool
  let token: String
  let refresh: String
  let profile: String?
}

enum AccountEndpoint {
  static func request(baseURL: URL, path: String, method: String = "GET", token: String? = nil)
    throws -> URLRequest
  {
    guard baseURL.scheme == "https", baseURL.host != nil else { throw NuboAPIError.configuration }
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.timeoutInterval = 20
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return request
  }

  static func signin(baseURL: URL, email: String, password: String) throws -> URLRequest {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !email.isEmpty, !password.isEmpty else { throw NuboAPIError.invalidRequest }
    var request = try request(baseURL: baseURL, path: "auth/signin", method: "POST")
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let encode: (String) -> String = { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }
    request.httpBody = Data("id=\(encode(email))&password=\(encode(password))".utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    return request
  }

  static func refresh(baseURL: URL, refresh: String) throws -> URLRequest {
    var request = try request(baseURL: baseURL, path: "auth/android/refresh", method: "POST")
    request.httpBody = try JSONEncoder().encode(["refresh": refresh])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  static func googleSignin(baseURL: URL, idToken: String) throws -> URLRequest {
    let idToken = idToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else { throw NuboAPIError.invalidRequest }
    var request = try request(baseURL: baseURL, path: "auth/android/google", method: "POST")
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let encoded = idToken.addingPercentEncoding(withAllowedCharacters: allowed)!
    request.httpBody = Data("id_token=\(encoded)".utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    return request
  }
}

protocol AccountServing: Sendable {
  func data(for request: URLRequest) async throws -> Data
  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens)
  func signinWithGoogle(idToken: String) async throws -> (AccountUser, AccountTokens)
  func load(token: String) async throws -> AccountUser
  func refresh(_ refresh: String) async throws -> AccountTokens
  func logout(token: String) async throws
}

extension AccountServing {
  func data(for request: URLRequest) async throws -> Data { throw NuboAPIError.configuration }
  func signinWithGoogle(idToken: String) async throws -> (AccountUser, AccountTokens) {
    throw NuboAPIError.configuration
  }
}

struct AccountService: AccountServing {
  func data(for request: URLRequest) async throws -> Data { try await client.data(for: request) }
  let baseURL: URL
  private let client: NuboAPIClient

  init(baseURL: URL, session: URLSession? = nil) {
    self.baseURL = baseURL
    // 인증 응답을 디스크 캐시나 공용 쿠키 저장소에 남기지 않는다.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    client = NuboAPIClient(
      apiBaseURL: baseURL,
      session: session
        ?? URLSession(
          configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil))
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    let data = try await client.data(
      for: AccountEndpoint.signin(baseURL: baseURL, email: email, password: password))
    let result = try JSONDecoder().decode(AccountEnvelope<AccountSigninResult>.self, from: data)
      .checked()
    return try checkedSignin(result)
  }

  func signinWithGoogle(idToken: String) async throws -> (AccountUser, AccountTokens) {
    let data = try await client.data(
      for: AccountEndpoint.googleSignin(baseURL: baseURL, idToken: idToken))
    let result = try JSONDecoder().decode(AccountEnvelope<AccountSigninResult>.self, from: data)
      .checked()
    return try checkedSignin(result)
  }

  func load(token: String) async throws -> AccountUser {
    let data = try await client.data(
      for: AccountEndpoint.request(baseURL: baseURL, path: "auth/load", token: token))
    let user = try JSONDecoder().decode(AccountEnvelope<AccountUser>.self, from: data).checked()
    guard user.uid > 0, !user.blocked else { throw NuboAPIError.httpStatus(401) }
    return user
  }

  func refresh(_ refresh: String) async throws -> AccountTokens {
    let data = try await client.data(
      for: AccountEndpoint.refresh(baseURL: baseURL, refresh: refresh))
    return try JSONDecoder().decode(AccountEnvelope<AccountTokens>.self, from: data).checked()
      .checked()
  }

  func logout(token: String) async throws {
    _ = try await client.data(
      for: AccountEndpoint.request(
        baseURL: baseURL, path: "auth/logout", method: "POST", token: token))
  }

  private func checkedSignin(_ result: AccountSigninResult) throws -> (AccountUser, AccountTokens) {
    let user = AccountUser(
      uid: result.uid, name: result.name, id: result.id, blocked: result.blocked,
      profile: result.profile)
    guard user.uid > 0, !user.blocked else { throw NuboAPIError.invalidResponse }
    return (user, try AccountTokens(token: result.token, refresh: result.refresh).checked())
  }
}

@MainActor
protocol AccountTokenStoring {
  func read() throws -> AccountTokens?
  func save(_ tokens: AccountTokens) throws
  func clear() throws
}

struct KeychainAccountStore: AccountTokenStoring {
  let service: String
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "session",
    ]
  }
  func read() throws -> AccountTokens? {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw AccountStorageError.unavailable
    }
    return try JSONDecoder().decode(AccountTokens.self, from: data).checked()
  }
  func save(_ tokens: AccountTokens) throws {
    let data = try JSONEncoder().encode(tokens.checked())
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
      guard status == errSecSuccess else { throw AccountStorageError.unavailable }
    } else if status != errSecSuccess {
      throw AccountStorageError.unavailable
    }
  }
  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AccountStorageError.unavailable
    }
  }
}

enum AccountStorageError: Error { case unavailable }

@MainActor @Observable
final class AccountSession {
  private(set) var user: AccountUser?
  private(set) var isBusy = false
  private(set) var error: String?
  private(set) var needsRestoration = true
  private let service: any AccountServing
  private let store: any AccountTokenStoring
  let apiBaseURL: URL?
  let postLikes = PhotoPostLikes()
  private var identity = UUID()
  var sessionIdentity: UUID { identity }
  private(set) var commentCounts: [Int: Int] = [:]
  private var writtenCommentIDs = Set<Int>()
  func recordComment(id: Int, postID: Int, baseline: Int) {
    guard writtenCommentIDs.insert(id).inserted else { return }
    commentCounts[postID] = max(0, commentCounts[postID] ?? baseline) + 1
  }
  func recordCommentRemoval(id: Int, postID: Int, baseline: Int, keepsPlaceholder: Bool) {
    guard !keepsPlaceholder else { return }
    writtenCommentIDs.remove(id)
    commentCounts[postID] = max(0, (commentCounts[postID] ?? baseline) - 1)
  }
  private var refreshTask: Task<AccountTokens, Error>?

  var profileURL: URL? {
    guard let apiBaseURL else { return nil }
    return MediaURLResolver.url(for: user?.profile ?? "", apiBaseURL: apiBaseURL)
  }
  private var tokens: AccountTokens?

  init(service: any AccountServing, store: any AccountTokenStoring, apiBaseURL: URL? = nil) {
    self.apiBaseURL = apiBaseURL
    self.service = service
    self.store = store
  }

  func signin(email: String, password: String) async {
    guard !isBusy else { return }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      let response = try await service.signin(email: email, password: password)
      try finishSignin(response)
    } catch is CancellationError { return } catch {
      self.error =
        error is AccountStorageError
        ? "로그인 정보를 안전하게 저장하지 못했어요. 기기 잠금을 해제한 뒤 다시 시도해 주세요."
        : "로그인하지 못했어요. 이메일·비밀번호와 네트워크 연결을 확인해 주세요."
    }
  }

  func signinWithGoogle(idToken: String) async {
    guard !isBusy else { return }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      let response = try await service.signinWithGoogle(idToken: idToken)
      try finishSignin(response)
    } catch is CancellationError { return } catch {
      self.error =
        error is AccountStorageError
        ? "로그인 정보를 안전하게 저장하지 못했어요. 기기 잠금을 해제한 뒤 다시 시도해 주세요."
        : "Google로 로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  func reportGoogleSignInFailure() {
    guard !isBusy else { return }
    error = "Google로 로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요."
  }

  private func finishSignin(_ response: (AccountUser, AccountTokens)) throws {
    try Task.checkCancellation()
    try store.save(response.1)
    identity = UUID()
    postLikes.reset()
    tokens = response.1
    user = response.0
    needsRestoration = false
  }

  func restore() async {
    guard needsRestoration, !isBusy else { return }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      guard var saved = try store.read() else {
        needsRestoration = false
        return
      }
      let loaded: AccountUser
      do {
        loaded = try await service.load(token: saved.token)
      } catch NuboAPIError.httpStatus(401) {
        do { saved = try await service.refresh(saved.refresh) } catch NuboAPIError.server(
          let code, _) where [2, 3, 4, 8].contains(code)
        {
          try store.clear()
          needsRestoration = false
          self.error = "로그인이 만료됐어요. 다시 로그인해 주세요."
          return
        }
        // 회전된 토큰 쌍은 후속 요청 전에 하나의 Keychain 항목으로 교체한다.
        try store.save(saved)
        loaded = try await service.load(token: saved.token)
      }
      try Task.checkCancellation()
      identity = UUID()
      postLikes.reset()
      tokens = saved
      user = loaded
      needsRestoration = false
    } catch is CancellationError { return } catch NuboAPIError.httpStatus(401) {
      do {
        try store.clear()
        needsRestoration = false
      } catch {}
      self.error = "로그인이 만료됐어요. 다시 로그인해 주세요."
    } catch {
      self.error = "로그인 상태를 확인하지 못했어요. 연결을 확인한 뒤 다시 시도해 주세요."
    }
  }

  func sendAuthenticated(_ request: URLRequest) async throws -> Data {
    guard let baseURL = apiBaseURL, let url = request.url,
      url.scheme == "https", url.host == baseURL.host, url.port == baseURL.port,
      url.path.hasPrefix(baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/")
    else { throw NuboAPIError.invalidRequest }
    guard let tokens, user != nil else { throw NuboAPIError.httpStatus(401) }
    let identity = identity
    func send(_ token: String) async throws -> Data {
      guard identity == self.identity, user != nil else { throw CancellationError() }
      var request = request
      request.httpShouldHandleCookies = false
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      let data = try await service.data(for: request)
      try Task.checkCancellation()
      guard identity == self.identity else { throw CancellationError() }
      return data
    }
    do { return try await send(tokens.token) } catch NuboAPIError.httpStatus(401) {
      guard identity == self.identity else { throw CancellationError() }
      let updated = try await refreshedTokens(after: tokens, identity: identity)
      do { return try await send(updated.token) } catch NuboAPIError.httpStatus(401) {
        if identity == self.identity { expireSession() }
        throw NuboAPIError.httpStatus(401)
      }
    }
  }

  private func refreshedTokens(after failed: AccountTokens, identity: UUID) async throws
    -> AccountTokens
  {
    if let tokens, tokens != failed { return tokens }
    if let refreshTask { return try await refreshTask.value }
    let task = Task { @MainActor in
      do {
        let updated = try await service.refresh(failed.refresh).checked()
        try Task.checkCancellation()
        guard identity == self.identity else { throw CancellationError() }
        try store.save(updated)
        tokens = updated
        return updated
      } catch NuboAPIError.server(let code, _) where [2, 3, 4, 8].contains(code) {
        if identity == self.identity { expireSession() }
        throw NuboAPIError.httpStatus(401)
      } catch NuboAPIError.httpStatus(401) {
        if identity == self.identity { expireSession() }
        throw NuboAPIError.httpStatus(401)
      }
    }
    refreshTask = task
    defer { if identity == self.identity { refreshTask = nil } }
    return try await task.value
  }

  private func expireSession() {
    identity = UUID()
    refreshTask = nil
    tokens = nil
    user = nil
    postLikes.reset()
    do {
      try store.clear()
      needsRestoration = false
      error = "로그인이 만료됐어요. 다시 로그인해 주세요."
    } catch {
      needsRestoration = true
      self.error = "로그인 정보를 지우지 못했어요. 기기 잠금을 해제한 뒤 다시 시도해 주세요."
    }
  }

  func logout() async {
    guard !isBusy else { return }
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      // 로컬 삭제가 실패하면 로그아웃 완료로 표시하지 않는다.
      try store.clear()
      identity = UUID()
      refreshTask?.cancel()
      refreshTask = nil
      postLikes.reset()
      let oldToken = tokens?.token
      tokens = nil
      user = nil
      needsRestoration = false
      if let oldToken { try? await service.logout(token: oldToken) }
    } catch {
      self.error = "로그인 정보를 지우지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}

// 인증 POST 본문이 리다이렉트를 통해 다른 주소로 전달되지 않게 한다.
private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
