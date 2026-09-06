import Foundation
import Observation
import SwiftUI

private struct DirectMessagePalette {
  let colorScheme: ColorScheme

  var background: Color {
    colorScheme == .dark
      ? Color(red: 28 / 255, green: 22 / 255, blue: 18 / 255)
      : Color(red: 248 / 255, green: 243 / 255, blue: 235 / 255)
  }

  var composer: Color {
    colorScheme == .dark
      ? Color(red: 45 / 255, green: 36 / 255, blue: 31 / 255)
      : Color(red: 242 / 255, green: 236 / 255, blue: 227 / 255)
  }

  var outgoing: Color {
    colorScheme == .dark
      ? Color(red: 91 / 255, green: 48 / 255, blue: 34 / 255)
      : Color(red: 178 / 255, green: 88 / 255, blue: 58 / 255)
  }

  var onOutgoing: Color {
    colorScheme == .dark
      ? Color(red: 255 / 255, green: 219 / 255, blue: 202 / 255)
      : Color(red: 255 / 255, green: 248 / 255, blue: 242 / 255)
  }

  var incoming: Color {
    colorScheme == .dark
      ? Color(red: 64 / 255, green: 54 / 255, blue: 48 / 255)
      : Color(red: 237 / 255, green: 229 / 255, blue: 217 / 255)
  }

  var onIncoming: Color {
    colorScheme == .dark
      ? Color(red: 236 / 255, green: 226 / 255, blue: 216 / 255)
      : Color(red: 48 / 255, green: 38 / 255, blue: 31 / 255)
  }

  var secondary: Color {
    colorScheme == .dark
      ? Color(red: 162 / 255, green: 152 / 255, blue: 142 / 255)
      : Color(red: 115 / 255, green: 100 / 255, blue: 90 / 255)
  }
}

struct DirectMessagePartner: Identifiable, Hashable, Sendable {
  let id: Int
  let name: String
  let profileURL: URL?

  init(id: Int, name: String, profileURL: URL?) {
    self.id = id
    self.name = name.nuboPlainText
    self.profileURL = profileURL
  }
}

struct DirectMessage: Identifiable, Equatable, Sendable {
  let id: Int
  let senderID: Int
  let text: String
  let sentAt: Date
  let readAt: Date?
}

struct DirectMessageThread: Identifiable, Equatable, Sendable {
  var id: Int { partner.id }
  let partner: DirectMessagePartner
  let latestMessageID: Int
  let latestText: String
  let sentAt: Date
}

private struct DirectMessageSenderDTO: Decodable {
  let uid: Int
  let name: String
  let profile: String
}

private struct DirectMessageThreadDTO: Decodable {
  let sender: DirectMessageSenderDTO
  let uid: Int
  let message: String
  let timestamp: Int64
}

private struct DirectMessageThreadResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: [DirectMessageThreadDTO]?

  func checked(apiBaseURL: URL) throws -> [DirectMessageThread] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    let items = result ?? []
    guard items.count <= 50 else { throw NuboAPIError.malformedResponse }
    var partnerIDs = Set<Int>()
    return try items.map { item in
      let name = item.sender.name.nuboPlainText
      let message = item.message.nuboPlainText
      guard item.uid > 0, item.sender.uid > 0, item.timestamp >= 0,
        !name.isEmpty, name.count <= 200, message.unicodeScalars.count <= 2_000,
        partnerIDs.insert(item.sender.uid).inserted
      else { throw NuboAPIError.malformedResponse }
      return DirectMessageThread(
        partner: DirectMessagePartner(
          id: item.sender.uid, name: name,
          profileURL: MediaURLResolver.url(for: item.sender.profile, apiBaseURL: apiBaseURL)),
        latestMessageID: item.uid, latestText: message,
        sentAt: Date(timeIntervalSince1970: Double(item.timestamp) / 1_000)
      )
    }
    .sorted { left, right in
      if left.sentAt == right.sentAt { return left.latestMessageID > right.latestMessageID }
      return left.sentAt > right.sentAt
    }
  }
}

private struct DirectMessageDTO: Decodable {
  let uid: Int
  let userUid: Int
  let message: String
  let timestamp: Int64
  let readAt: Int64?
}

private struct DirectMessageHistoryResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: [DirectMessageDTO]?

  func checked() throws -> [DirectMessage] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    let items = result ?? []
    guard items.count <= 100 else { throw NuboAPIError.malformedResponse }
    var messageIDs = Set<Int>()
    return try items.map { item in
      let message = item.message.nuboPlainText
      let readAt = item.readAt ?? 0
      guard item.uid > 0, item.userUid > 0, item.timestamp >= 0, !message.isEmpty,
        readAt >= 0, message.unicodeScalars.count <= 2_000,
        messageIDs.insert(item.uid).inserted
      else { throw NuboAPIError.malformedResponse }
      return DirectMessage(
        id: item.uid, senderID: item.userUid, text: message,
        sentAt: Date(timeIntervalSince1970: Double(item.timestamp) / 1_000),
        readAt: readAt > 0 ? Date(timeIntervalSince1970: Double(readAt) / 1_000) : nil)
    }
    .sorted { left, right in
      if left.sentAt == right.sentAt { return left.id < right.id }
      return left.sentAt < right.sentAt
    }
  }
}

private struct DirectMessageSendBody: Encodable {
  let targetUserUid: Int
  let message: String
}

private struct DirectMessageSendResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: Int?

  func checked() throws -> Int {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    guard let result, result > 0 else { throw NuboAPIError.malformedResponse }
    return result
  }
}

private struct DirectMessageReadBody: Encodable {
  let targetUserUid: Int
  let throughUid: Int
}

private struct DirectMessageReadResponseDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: Result?

  struct Result: Decodable {
    let throughUid: Int
    let readAt: Int64
    let updatedCount: Int64
  }

  func checked(expectedThroughID: Int) throws {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    guard let result, result.throughUid == expectedThroughID, result.readAt >= 0,
      result.updatedCount >= 0
    else { throw NuboAPIError.malformedResponse }
  }
}

enum DirectMessageEndpoint {
  static func threads(baseURL: URL, limit: Int = 30) throws -> URLRequest {
    guard (1...50).contains(limit) else { throw NuboAPIError.invalidRequest }
    return try request(
      baseURL: baseURL, path: "chat/list",
      queryItems: [URLQueryItem(name: "limit", value: String(limit))])
  }

  static func history(baseURL: URL, targetUserID: Int, limit: Int = 100) throws -> URLRequest {
    guard targetUserID > 0, (1...100).contains(limit) else {
      throw NuboAPIError.invalidRequest
    }
    return try request(
      baseURL: baseURL, path: "chat/history",
      queryItems: [
        URLQueryItem(name: "targetUserUid", value: String(targetUserID)),
        URLQueryItem(name: "limit", value: String(limit)),
      ])
  }

  static func send(baseURL: URL, targetUserID: Int, message: String) throws -> URLRequest {
    let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard targetUserID > 0, !message.isEmpty, message.unicodeScalars.count <= 2_000 else {
      throw NuboAPIError.invalidRequest
    }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "chat/save", method: "POST")
    request.httpBody = try JSONEncoder().encode(
      DirectMessageSendBody(targetUserUid: targetUserID, message: message))
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  static func markRead(baseURL: URL, targetUserID: Int, throughID: Int) throws -> URLRequest {
    guard targetUserID > 0, throughID > 0 else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "chat/read", method: "PATCH")
    request.httpBody = try JSONEncoder().encode(
      DirectMessageReadBody(targetUserUid: targetUserID, throughUid: throughID))
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  private static func request(
    baseURL: URL, path: String, queryItems: [URLQueryItem]
  ) throws -> URLRequest {
    var components = URLComponents(
      url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
    components?.queryItems = queryItems
    guard let url = components?.url else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(baseURL: baseURL, path: path)
    request.url = url
    return request
  }
}

enum DirectMessageHashtags {
  private static let expression = try! NSRegularExpression(
    pattern: #"(?<![\p{L}\p{N}_])#[\p{L}\p{N}_]+"#)

  static func keywords(in text: String) -> [String] {
    matches(in: text).map(\.keyword)
  }

  static func linkedText(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    for match in matches(in: text) {
      guard let attributedRange = Range(match.range, in: attributed),
        let url = link(for: match.keyword)
      else { continue }
      attributed[attributedRange].link = url
      attributed[attributedRange].underlineStyle = .single
    }
    return attributed
  }

  static func keyword(from url: URL) -> String? {
    guard url.scheme == "sensta", url.host == "hashtag",
      let keyword = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "keyword" })?.value?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !keyword.isEmpty
    else { return nil }
    return keyword
  }

  private static func link(for keyword: String) -> URL? {
    var components = URLComponents()
    components.scheme = "sensta"
    components.host = "hashtag"
    components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
    return components.url
  }

  private static func matches(in text: String) -> [(range: Range<String.Index>, keyword: String)] {
    expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      guard let range = Range(match.range, in: text) else { return nil }
      return (range, String(text[range].dropFirst()))
    }
  }
}

@MainActor @Observable
final class DirectMessageThreadListModel {
  private(set) var threads: [DirectMessageThread] = []
  private(set) var isLoading = false
  private(set) var error: String?
  private var loadedIdentity: UUID?

  func load(using account: AccountSession, force: Bool = false) async {
    guard account.user != nil, let baseURL = account.apiBaseURL else {
      threads = []
      error = nil
      loadedIdentity = nil
      return
    }
    let identity = account.sessionIdentity
    guard force || loadedIdentity != identity, !isLoading else { return }
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let request = try DirectMessageEndpoint.threads(baseURL: baseURL)
      let data = try await account.sendAuthenticated(request)
      let result = try JSONDecoder().decode(DirectMessageThreadResponseDTO.self, from: data)
        .checked(apiBaseURL: baseURL)
      try Task.checkCancellation()
      guard identity == account.sessionIdentity else { return }
      threads = result
      loadedIdentity = identity
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      self.error = "메시지 목록을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}

@MainActor @Observable
final class DirectMessageModel {
  var draft = ""
  private(set) var messages: [DirectMessage] = []
  private(set) var isLoading = false
  private(set) var isSending = false
  private(set) var loadError: String?
  private(set) var sendError: String?
  private var loadedTargetID: Int?
  private var loadedIdentity: UUID?
  private var markedThroughID: Int?
  private var refreshInProgress = false
  private var refreshRequested = false
  private var messageGeneration = 0

  var draftLength: Int { draft.unicodeScalars.count }
  var canSend: Bool {
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.unicodeScalars.count <= 2_000 && !isLoading && !isSending
  }

  func load(
    partner: DirectMessagePartner, using account: AccountSession, force: Bool = false,
    quietly: Bool = false
  ) async
  {
    guard let user = account.user, user.uid != partner.id, let baseURL = account.apiBaseURL else {
      messages = []
      loadError = nil
      loadedIdentity = nil
      loadedTargetID = nil
      markedThroughID = nil
      refreshRequested = false
      return
    }
    let identity = account.sessionIdentity
    let currentMessageGeneration = messageGeneration
    if loadedTargetID != partner.id || loadedIdentity != identity { markedThroughID = nil }
    guard force || loadedTargetID != partner.id || loadedIdentity != identity else {
      return
    }
    if refreshInProgress {
      if force { refreshRequested = true }
      return
    }
    refreshInProgress = true
    if !quietly {
      isLoading = true
      loadError = nil
    }
    defer {
      refreshInProgress = false
      if !quietly { isLoading = false }
      if refreshRequested {
        refreshRequested = false
        Task { @MainActor [weak self] in
          await self?.load(partner: partner, using: account, force: true, quietly: true)
        }
      }
    }
    do {
      let request = try DirectMessageEndpoint.history(
        baseURL: baseURL, targetUserID: partner.id)
      let data = try await account.sendAuthenticated(request)
      let result = try JSONDecoder().decode(DirectMessageHistoryResponseDTO.self, from: data)
        .checked()
      try Task.checkCancellation()
      guard identity == account.sessionIdentity else { return }
      guard currentMessageGeneration == messageGeneration else { return }
      messages = result
      loadedTargetID = partner.id
      loadedIdentity = identity
      await markReadIfNeeded(
        messages: result, partner: partner, account: account, identity: identity, baseURL: baseURL)
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      loadError = "대화 내용을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  func send(to partner: DirectMessagePartner, using account: AccountSession) async {
    let outgoing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSend, let user = account.user, user.uid != partner.id,
      let baseURL = account.apiBaseURL
    else { return }
    let identity = account.sessionIdentity
    isSending = true
    sendError = nil
    defer { isSending = false }
    do {
      let request = try DirectMessageEndpoint.send(
        baseURL: baseURL, targetUserID: partner.id, message: outgoing)
      let data = try await account.sendAuthenticated(request)
      let messageID = try JSONDecoder().decode(DirectMessageSendResponseDTO.self, from: data)
        .checked()
      try Task.checkCancellation()
      guard identity == account.sessionIdentity else { return }
      if !messages.contains(where: { $0.id == messageID }) {
        messageGeneration += 1
        messages.append(
          DirectMessage(
            id: messageID, senderID: user.uid, text: outgoing, sentAt: .now, readAt: nil))
      }
      if draft.trimmingCharacters(in: .whitespacesAndNewlines) == outgoing { draft = "" }
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      sendError = "메시지를 보내지 못했어요. 연결 또는 상대방과의 차단 상태를 확인해 주세요."
    }
  }

  private func markReadIfNeeded(
    messages: [DirectMessage], partner: DirectMessagePartner, account: AccountSession,
    identity: UUID, baseURL: URL
  ) async {
    guard let throughID = messages.last(where: { $0.senderID == partner.id })?.id,
      throughID > (markedThroughID ?? 0)
    else { return }
    do {
      let request = try DirectMessageEndpoint.markRead(
        baseURL: baseURL, targetUserID: partner.id, throughID: throughID)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(DirectMessageReadResponseDTO.self, from: data)
        .checked(expectedThroughID: throughID)
      try Task.checkCancellation()
      guard identity == account.sessionIdentity else { return }
      markedThroughID = throughID
    } catch is CancellationError {
    } catch {
      // 대화 표시는 유지하고 다음 polling에서 읽음 처리를 다시 시도한다.
    }
  }
}

struct DirectMessageThreadListView: View {
  let account: AccountSession
  let feedService: (any PhotoFeedServing)?
  let detailService: (any PhotoPostDetailServing)?
  @State private var model = DirectMessageThreadListModel()

  init(
    account: AccountSession, feedService: (any PhotoFeedServing)? = nil,
    detailService: (any PhotoPostDetailServing)? = nil
  ) {
    self.account = account
    self.feedService = feedService
    self.detailService = detailService
  }

  var body: some View {
    Group {
      if model.isLoading && model.threads.isEmpty {
        ProgressView("메시지를 불러오는 중…")
      } else if let error = model.error, model.threads.isEmpty {
        ContentUnavailableView {
          Label("메시지를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
        } description: {
          Text(error)
        } actions: {
          Button("다시 시도") { Task { await model.load(using: account, force: true) } }
        }
      } else if model.threads.isEmpty {
        ContentUnavailableView(
          "아직 받은 메시지가 없어요", systemImage: "bubble.left.and.bubble.right",
          description: Text("사진가 프로필에서 1:1 대화를 시작할 수 있어요."))
      } else {
        List(model.threads) { thread in
          NavigationLink {
            DirectMessageView(
              partner: thread.partner, account: account, feedService: feedService,
              detailService: detailService)
          } label: {
            DirectMessageThreadRow(thread: thread)
          }
          .accessibilityIdentifier("direct-message-thread-\(thread.partner.id)")
        }
        .listStyle(.plain)
        .refreshable { await model.load(using: account, force: true) }
      }
    }
    .navigationTitle("1:1 메시지")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: account.sessionIdentity) { await model.load(using: account) }
  }
}

private struct DirectMessageThreadRow: View {
  let thread: DirectMessageThread

  var body: some View {
    HStack(spacing: 12) {
      AccountAvatar(url: thread.partner.profileURL, size: 46)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(thread.partner.name).font(.headline).lineLimit(1)
          Spacer(minLength: 8)
          Text(thread.sentAt, format: .relative(presentation: .named))
            .font(.caption2).foregroundStyle(.secondary)
        }
        Text(thread.latestText.isEmpty ? "새 메시지" : thread.latestText)
          .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

private struct DirectMessagePollingID: Equatable {
  let identity: UUID
  let partnerID: Int
  let isActive: Bool
}

struct DirectMessageView: View {
  let partner: DirectMessagePartner
  let account: AccountSession
  let feedService: (any PhotoFeedServing)?
  let detailService: (any PhotoPostDetailServing)?
  private let pushNotifications: PushNotificationManager
  @State private var model = DirectMessageModel()
  @State private var selectedHashtag: String?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var composerFocused: Bool
  private static let bottomAnchorID = "direct-message-bottom"

  private var palette: DirectMessagePalette {
    DirectMessagePalette(colorScheme: colorScheme)
  }

  init(
    partner: DirectMessagePartner, account: AccountSession,
    feedService: (any PhotoFeedServing)? = nil,
    detailService: (any PhotoPostDetailServing)? = nil,
    pushNotifications: PushNotificationManager = .shared
  ) {
    self.partner = partner
    self.account = account
    self.feedService = feedService
    self.detailService = detailService
    self.pushNotifications = pushNotifications
  }

  var body: some View {
    @Bindable var model = model
    ScrollViewReader { proxy in
      Group {
        if model.isLoading && model.messages.isEmpty {
          ProgressView("대화를 불러오는 중…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError, model.messages.isEmpty {
          ContentUnavailableView {
            Label("대화를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
          } description: {
            Text(error)
          } actions: {
            Button("다시 시도") {
              Task { await model.load(partner: partner, using: account, force: true) }
            }
          }
        } else {
          ScrollView {
            LazyVStack(spacing: 12) {
              if model.messages.isEmpty {
                ContentUnavailableView(
                  "아직 나눈 대화가 없어요", systemImage: "bubble.left.and.bubble.right",
                  description: Text("첫 메시지로 사진 이야기를 시작해 보세요.")
                )
                .padding(.top, 60)
              }
              ForEach(model.messages) { message in
                messageBubble(
                  message,
                  isLatestMine: message.id
                    == model.messages.last(where: { $0.senderID == account.user?.uid })?.id)
                  .id(message.id)
              }
              Color.clear
                .frame(height: 24)
                .id(Self.bottomAnchorID)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
          }
          .background(palette.background)
          .scrollDismissesKeyboard(.interactively)
          .refreshable {
            await model.load(partner: partner, using: account, force: true)
          }
        }
      }
      .onChange(of: model.messages.last?.id, initial: true) { _, messageID in
        guard messageID != nil else { return }
        scrollToBottom(proxy, animated: !reduceMotion)
      }
      .onAppear {
        scrollToBottom(proxy, animated: false)
      }
      .onChange(of: composerFocused) { _, focused in
        guard focused else { return }
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(180))
          scrollToBottom(proxy, animated: !reduceMotion)
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        if let error = model.sendError {
          Label(error, systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("direct-message-send-error")
        }
        HStack(alignment: .bottom, spacing: 10) {
          TextField("메시지를 입력해 주세요", text: $model.draft, axis: .vertical)
            .lineLimit(1...5)
            .textFieldStyle(.roundedBorder)
            .focused($composerFocused)
            .submitLabel(.send)
            .onSubmit { send() }
            .accessibilityIdentifier("direct-message-input")
          Button(action: send) {
            if model.isSending {
              ProgressView().frame(width: 30, height: 30)
            } else {
              Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
            }
          }
          .disabled(!model.canSend)
          .accessibilityLabel("메시지 전송")
          .accessibilityIdentifier("direct-message-send")
        }
        HStack {
          Label("개인정보는 메시지로 공유하지 마세요.", systemImage: "lock.shield")
          Spacer()
          Text("\(model.draftLength.formatted())/2,000")
            .foregroundStyle(model.draftLength > 2_000 ? Color.red : Color.secondary)
            .accessibilityLabel("메시지 길이 \(model.draftLength), 최대 2,000자")
        }
        .font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(palette.composer)
    }
    .background(palette.background.ignoresSafeArea())
    .navigationTitle(partner.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(palette.background, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        HStack(spacing: 8) {
          AccountAvatar(
            url: partner.profileURL, size: 30,
            accessibilityLabel: "\(partner.name) 프로필 사진")
          Text(partner.name).font(.headline).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("direct-message-partner")
      }
    }
    .navigationDestination(item: $selectedHashtag) { hashtag in
      hashtagSearchDestination(hashtag)
    }
    .task(
      id: DirectMessagePollingID(
        identity: account.sessionIdentity, partnerID: partner.id,
        isActive: scenePhase == .active)
    ) {
      guard scenePhase == .active else { return }
      await model.load(partner: partner, using: account, force: true)
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(12)) } catch { return }
        await model.load(partner: partner, using: account, force: true, quietly: true)
      }
    }
    .onChange(of: pushNotifications.latestEvent, initial: true) { _, event in
      guard case .directMessage(let senderID) = event?.destination,
        senderID == partner.id
      else { return }
      Task {
        await model.load(
          partner: partner, using: account, force: true, quietly: !model.messages.isEmpty)
      }
    }
  }

  private func send() {
    Task { await model.send(to: partner, using: account) }
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
    Task { @MainActor in
      await Task.yield()
      if animated {
        withAnimation(.easeOut(duration: 0.22)) {
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
      } else {
        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
      }
    }
  }

  private func messageBubble(_ message: DirectMessage, isLatestMine: Bool) -> some View {
    let mine = message.senderID == account.user?.uid
    return HStack(alignment: .center, spacing: 8) {
      if mine { Spacer(minLength: 44) }
      if !mine {
        AccountAvatar(
          url: partner.profileURL, size: 34,
          accessibilityLabel: "\(partner.name) 프로필 사진")
          .accessibilityIdentifier("direct-message-avatar-\(message.id)")
      }
      VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
        Text(DirectMessageHashtags.linkedText(message.text))
          .font(.body)
          .foregroundStyle(mine ? palette.onOutgoing : palette.onIncoming)
          .tint(mine ? palette.onOutgoing : Color.accentColor)
          .fixedSize(horizontal: false, vertical: true)
          .environment(
            \.openURL,
            OpenURLAction { url in
              guard let hashtag = DirectMessageHashtags.keyword(from: url) else {
                return .discarded
              }
              selectedHashtag = hashtag
              return .handled
            })
        HStack(spacing: 8) {
          Text(message.sentAt, format: .dateTime.month().day().hour().minute())
            .font(.caption2)
            .foregroundStyle(mine ? palette.onOutgoing.opacity(0.72) : palette.secondary)
          if mine && isLatestMine {
            Text(message.readAt == nil ? "전송됨" : "읽음")
              .font(.caption2.weight(.medium))
              .foregroundStyle(palette.onOutgoing.opacity(0.9))
              .accessibilityIdentifier("direct-message-read-\(message.id)")
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        mine ? AnyShapeStyle(palette.outgoing) : AnyShapeStyle(palette.incoming),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      if mine {
        AccountAvatar(
          url: account.profileURL, size: 34,
          accessibilityLabel: "내 프로필 사진")
          .accessibilityIdentifier("direct-message-avatar-\(message.id)")
      }
      if !mine { Spacer(minLength: 44) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(mine ? "내 메시지" : "\(partner.name)의 메시지")
    .accessibilityValue(
      "\(message.text), \(message.sentAt.formatted())\(mine && isLatestMine ? (message.readAt == nil ? ", 전송됨" : ", 읽음") : "")"
    )
    .accessibilityIdentifier("direct-message-\(message.id)")
  }

  @ViewBuilder
  private func hashtagSearchDestination(_ hashtag: String) -> some View {
    let initialRequest = PhotoSearchRequest(keyword: hashtag, option: .hashtag)
    if let feedService, let detailService {
      PhotoSearchView(
        service: feedService, detailService: detailService, initialRequest: initialRequest)
    } else if let baseURL = account.apiBaseURL {
      PhotoSearchView(
        service: PhotoFeedService(apiBaseURL: baseURL),
        detailService: PhotoPostDetailService(apiBaseURL: baseURL),
        initialRequest: initialRequest)
    } else {
      ContentUnavailableView(
        "탐색을 열 수 없어요", systemImage: "magnifyingglass",
        description: Text("앱 설정을 확인한 뒤 다시 시도해 주세요."))
    }
  }
}
