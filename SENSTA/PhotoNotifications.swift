import Foundation
import Observation
import SwiftUI

struct PhotoNotification: Identifiable, Equatable, Sendable {
  let id: Int
  let senderID: Int
  let senderName: String
  let senderProfileURL: URL?
  let type: Int
  let postID: Int
  let isRead: Bool
  let submitted: Date

  var message: String {
    switch type {
    case 0: "내 게시글을 좋아합니다"
    case 1: "내 댓글을 좋아합니다"
    case 2: "내 게시글에 댓글을 남겼습니다"
    case 3: "내 댓글에 답글을 남겼습니다"
    default: "나에게 메시지를 보냈습니다"
    }
  }

  var systemImage: String {
    switch type {
    case 0: "heart.fill"
    case 1: "heart"
    case 2: "text.bubble"
    case 3: "arrowshape.turn.up.left"
    default: "message"
    }
  }
}

struct PhotoNotificationResponseDTO: Decodable, Sendable {
  let success: Bool
  let error: String
  let code: Int
  let result: [PhotoNotificationDTO]?

  func makeNotifications(apiBaseURL: URL) throws -> [PhotoNotification] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    return (result ?? []).map { $0.makeNotification(apiBaseURL: apiBaseURL) }
  }
}

struct PhotoNotificationDTO: Decodable, Sendable {
  let uid: Int
  let fromUser: PhotoNotificationWriterDTO
  let type: Int
  let postUid: Int
  let checked: Bool
  let timestamp: Int64

  func makeNotification(apiBaseURL: URL) -> PhotoNotification {
    PhotoNotification(
      id: uid,
      senderID: fromUser.uid,
      senderName: fromUser.name,
      senderProfileURL: MediaURLResolver.url(for: fromUser.profile, apiBaseURL: apiBaseURL),
      type: type,
      postID: postUid,
      isRead: checked,
      submitted: Date(timeIntervalSince1970: Double(timestamp) / 1_000)
    )
  }
}

struct PhotoNotificationWriterDTO: Decodable, Sendable {
  let uid: Int
  let name: String
  let profile: String
}

private struct PhotoNotificationAcknowledgementDTO: Decodable {
  let success: Bool
  let error: String?
  let code: Int

  func checked() throws {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error ?? "") }
  }
}

enum PhotoNotificationEndpoint {
  static func list(baseURL: URL, limit: Int = 20) throws -> URLRequest {
    guard (1...100).contains(limit),
      var components = URLComponents(
        url: baseURL.appending(path: "home/noti/load"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func markRead(baseURL: URL, notificationID: Int) throws -> URLRequest {
    guard notificationID > 0 else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(
      url: baseURL.appending(path: "home/noti/checked/\(notificationID)"))
    request.httpMethod = "PATCH"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func markAllRead(baseURL: URL) -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: "home/noti/checked"))
    request.httpMethod = "PATCH"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

@MainActor @Observable
final class PhotoNotificationCenter {
  private(set) var notifications: [PhotoNotification] = []
  private(set) var isLoading = false
  private(set) var error: String?
  private var loadedIdentity: UUID?

  var hasUnread: Bool { notifications.contains { !$0.isRead } }

  func reset() {
    notifications = []
    error = nil
    isLoading = false
    loadedIdentity = nil
  }

  func load(using account: AccountSession, force: Bool = false) async {
    guard account.user != nil, let baseURL = account.apiBaseURL else {
      reset()
      return
    }
    let identity = account.sessionIdentity
    guard force || loadedIdentity != identity else { return }
    guard !isLoading else { return }
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let data = try await account.sendAuthenticated(
        PhotoNotificationEndpoint.list(baseURL: baseURL))
      let decoded = try JSONDecoder().decode(PhotoNotificationResponseDTO.self, from: data)
        .makeNotifications(apiBaseURL: baseURL)
      guard identity == account.sessionIdentity else { return }
      notifications = decoded
      loadedIdentity = identity
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      self.error = "알림을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  func markRead(_ notification: PhotoNotification, using account: AccountSession) async {
    guard !notification.isRead, let baseURL = account.apiBaseURL else { return }
    let identity = account.sessionIdentity
    do {
      let data = try await account.sendAuthenticated(
        PhotoNotificationEndpoint.markRead(baseURL: baseURL, notificationID: notification.id))
      try JSONDecoder().decode(PhotoNotificationAcknowledgementDTO.self, from: data).checked()
      guard identity == account.sessionIdentity else { return }
      notifications = notifications.map { item in
        guard item.id == notification.id else { return item }
        return PhotoNotification(
          id: item.id, senderID: item.senderID, senderName: item.senderName,
          senderProfileURL: item.senderProfileURL, type: item.type, postID: item.postID,
          isRead: true, submitted: item.submitted)
      }
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      self.error = "알림을 읽음으로 바꾸지 못했어요."
    }
  }

  func markAllRead(using account: AccountSession) async {
    guard hasUnread, let baseURL = account.apiBaseURL else { return }
    let identity = account.sessionIdentity
    do {
      let data = try await account.sendAuthenticated(
        PhotoNotificationEndpoint.markAllRead(baseURL: baseURL))
      try JSONDecoder().decode(PhotoNotificationAcknowledgementDTO.self, from: data).checked()
      guard identity == account.sessionIdentity else { return }
      notifications = notifications.map { item in
        PhotoNotification(
          id: item.id, senderID: item.senderID, senderName: item.senderName,
          senderProfileURL: item.senderProfileURL, type: item.type, postID: item.postID,
          isRead: true, submitted: item.submitted)
      }
    } catch is CancellationError {
    } catch {
      guard identity == account.sessionIdentity else { return }
      self.error = "알림을 모두 읽음으로 바꾸지 못했어요."
    }
  }
}

struct PhotoNotificationBell: View {
  let hasUnread: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var vibration = 0

  var body: some View {
    Image(systemName: hasUnread ? "bell.fill" : "bell")
      .font(.body.weight(.medium))
      .foregroundStyle(.white)
      .phaseAnimator(reduceMotion ? [0.0] : [0.0, -10, 10, -7, 7, 0], trigger: vibration) {
        content, angle in
        content.rotationEffect(.degrees(angle))
      } animation: { _ in
        .easeInOut(duration: 0.1)
      }
      .frame(width: 44, height: 44)
      .background(.black.opacity(0.25), in: Circle())
      .overlay(alignment: .topTrailing) {
        if hasUnread {
          Circle()
            .fill(.red)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .padding(5)
            .accessibilityHidden(true)
        }
      }
      .onAppear { animateIfNeeded() }
      .onChange(of: hasUnread) { _, _ in animateIfNeeded() }
  }

  private func animateIfNeeded() {
    guard hasUnread, !reduceMotion else { return }
    vibration += 1
  }
}

struct PhotoNotificationsView: View {
  let center: PhotoNotificationCenter
  let account: AccountSession
  let detailService: any PhotoPostDetailServing
  let feedService: (any PhotoFeedServing)?

  init(
    center: PhotoNotificationCenter, account: AccountSession,
    detailService: any PhotoPostDetailServing, feedService: (any PhotoFeedServing)? = nil
  ) {
    self.center = center
    self.account = account
    self.detailService = detailService
    self.feedService = feedService
  }

  var body: some View {
    Group {
      if center.isLoading && center.notifications.isEmpty {
        ProgressView("알림을 불러오는 중…")
      } else if center.notifications.isEmpty {
        ContentUnavailableView(
          "확인할 알림이 없어요",
          systemImage: "bell.slash",
          description: Text("새로운 활동이 생기면 이곳에서 알려드릴게요."))
      } else {
        List(center.notifications) { notification in
          if notification.type == 4 {
            NavigationLink {
              DirectMessageView(
                partner: DirectMessagePartner(
                  id: notification.senderID, name: notification.senderName,
                  profileURL: notification.senderProfileURL),
                account: account, feedService: feedService, detailService: detailService
              )
              .task { await center.markRead(notification, using: account) }
            } label: {
              notificationRow(notification)
            }
          } else if notification.postID <= 0 {
            Button {
              Task { await center.markRead(notification, using: account) }
            } label: {
              notificationRow(notification)
            }
            .buttonStyle(.plain)
          } else {
            NavigationLink {
              PhotoPostDetailView(postID: notification.postID, service: detailService)
                .task { await center.markRead(notification, using: account) }
            } label: {
              notificationRow(notification)
            }
          }
        }
        .listStyle(.plain)
        .refreshable { await center.load(using: account, force: true) }
      }
    }
    .navigationTitle("알림")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if center.hasUnread {
        ToolbarItem(placement: .topBarTrailing) {
          Button("모두 읽음") { Task { await center.markAllRead(using: account) } }
            .accessibilityIdentifier("notification-mark-all-read")
        }
      }
    }
    .overlay(alignment: .bottom) {
      if let error = center.error {
        Text(error)
          .font(.footnote)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(.regularMaterial, in: Capsule())
          .padding()
          .accessibilityIdentifier("notification-error")
      }
    }
    .task { await center.load(using: account, force: true) }
  }

  private func notificationRow(_ notification: PhotoNotification) -> some View {
    HStack(spacing: 12) {
      Image(systemName: notification.systemImage)
        .foregroundStyle(notification.isRead ? Color.secondary : Color.accentColor)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        Text("\(notification.senderName)님이 \(notification.message)")
          .fontWeight(notification.isRead ? .regular : .semibold)
        Text(notification.submitted, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      if !notification.isRead {
        Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true)
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("notification-\(notification.id)")
  }
}
