import FirebaseCore
@preconcurrency import FirebaseMessaging
import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

enum PushAuthorizationState: Equatable, Sendable {
  case unavailable
  case unknown
  case notDetermined
  case denied
  case authorized
}

struct PushDeviceResponseDTO: Decodable, Sendable {
  let success: Bool
  let error: String?
  let code: Int

  func checked() throws {
    guard success, code == 0 else {
      throw NuboAPIError.server(code: code, message: error ?? "")
    }
  }
}

private struct PushDeviceBody: Encodable {
  let token: String
  let platform: String
}

enum PushDeviceEndpoint {
  static func register(baseURL: URL, installationID: String) throws -> URLRequest {
    try request(baseURL: baseURL, installationID: installationID, method: "POST")
  }

  static func unregister(baseURL: URL, installationID: String) throws -> URLRequest {
    try request(baseURL: baseURL, installationID: installationID, method: "DELETE")
  }

  private static func request(baseURL: URL, installationID: String, method: String) throws
    -> URLRequest
  {
    let installationID = installationID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (20...512).contains(installationID.count) else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(
      baseURL: baseURL, path: "push/device", method: method)
    request.httpBody = try JSONEncoder().encode(
      PushDeviceBody(token: installationID, platform: "ios"))
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }
}

enum RemoteNotificationDestination: Hashable, Sendable {
  case post(Int)
  case directMessage(Int)

  static func make(from userInfo: [AnyHashable: Any]) -> Self? {
    guard let type = integer(userInfo["type"]) else { return nil }
    if type == 4, let senderID = integer(userInfo["fromUserUid"]), senderID > 0 {
      return .directMessage(senderID)
    }
    guard let postID = integer(userInfo["postUid"]), postID > 0 else { return nil }
    return .post(postID)
  }

  private static func integer(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }
}

struct RemoteNotificationEvent: Equatable, Sendable {
  let id = UUID()
  let destination: RemoteNotificationDestination
}

@MainActor
protocol AccountLogoutCoordinating: AnyObject {
  func prepareForLogout(using account: AccountSession) async
}

final class SENSTAAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    PushNotificationManager.shared.configure(application: application, launchOptions: launchOptions)
    return true
  }

  // SwiftUI 생명주기에서도 Firebase의 APNs token swizzling이 전달받을 진입점이 필요하다.
  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {}

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error)
  }
}

@MainActor @Observable
final class PushNotificationManager: NSObject, AccountLogoutCoordinating {
  static let shared = PushNotificationManager()

  private(set) var authorizationState: PushAuthorizationState = .unknown
  private(set) var isConfigured = false
  private(set) var registrationError: String?
  private(set) var destination: RemoteNotificationDestination?
  private(set) var latestEvent: RemoteNotificationEvent?

  @ObservationIgnored private weak var account: AccountSession?
  @ObservationIgnored private weak var application: UIApplication?
  @ObservationIgnored private var installationID: String?
  @ObservationIgnored private var serverRegistration: ServerRegistration?
  @ObservationIgnored private var isActivating = false

  private struct ServerRegistration: Equatable {
    let identity: UUID
    let installationID: String
  }

  private override init() { super.init() }

  func configure(
    application: UIApplication,
    launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) {
    self.application = application
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.delegate = self

    guard FirebaseApp.app() == nil,
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let options = FirebaseOptions(contentsOfFile: path),
      options.bundleID == Bundle.main.bundleIdentifier
    else {
      authorizationState = .unavailable
      return
    }

    FirebaseApp.configure(options: options)
    isConfigured = true
    Messaging.messaging().delegate = self
    debugLog("Firebase configured for \(options.bundleID)")

    if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      receive(userInfo: userInfo)
    }
    Task { await refreshAuthorizationStatus() }
  }

  func synchronize(with account: AccountSession) async {
    self.account = account
    account.logoutCoordinator = self
    guard isConfigured else { return }
    await refreshAuthorizationStatus()

    guard account.user != nil else {
      serverRegistration = nil
      if !account.needsRestoration { await deactivateMessaging() }
      return
    }
    guard authorizationState == .authorized else { return }
    await activateMessaging()
    await registerServerDeviceIfNeeded()
  }

  func requestAuthorization() async {
    guard isConfigured else { return }
    do {
      _ = try await UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .badge, .sound])
      await refreshAuthorizationStatus()
      guard authorizationState == .authorized else { return }
      await activateMessaging()
      await registerServerDeviceIfNeeded()
    } catch {
      registrationError = "푸시 알림 권한을 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  func retryRegistration() async {
    guard authorizationState == .authorized else { return }
    registrationError = nil
    serverRegistration = nil
    await activateMessaging()
    await registerServerDeviceIfNeeded()
  }

  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    application?.open(url)
  }

  func clearDestination() { destination = nil }

  func prepareForLogout(using account: AccountSession) async {
    await unregisterServerDevice(using: account)
    await deactivateMessaging()
    self.account = nil
  }

  func didFailToRegisterForRemoteNotifications(_ error: Error) {
    debugLog("APNs registration failed: \(error.localizedDescription)")
    registrationError = "Apple 푸시 서비스에 연결하지 못했어요. 네트워크를 확인해 주세요."
  }

  private func refreshAuthorizationStatus() async {
    guard isConfigured else {
      authorizationState = .unavailable
      return
    }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
      authorizationState = .notDetermined
    case .denied:
      authorizationState = .denied
    case .authorized, .provisional, .ephemeral:
      authorizationState = .authorized
    @unknown default:
      authorizationState = .unknown
    }
  }

  private func activateMessaging() async {
    guard isConfigured, !isActivating else { return }
    isActivating = true
    defer { isActivating = false }
    application?.registerForRemoteNotifications()
    Messaging.messaging().isAutoInitEnabled = true
    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        Messaging.messaging().register { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
      }
    } catch {
      registrationError = "푸시 알림을 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  private func deactivateMessaging() async {
    guard isConfigured else { return }
    Messaging.messaging().isAutoInitEnabled = false
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      Messaging.messaging().unregister { _ in continuation.resume() }
    }
    installationID = nil
    serverRegistration = nil
  }

  private func registerServerDeviceIfNeeded() async {
    guard let account, account.user != nil, let baseURL = account.apiBaseURL,
      let installationID, authorizationState == .authorized
    else { return }
    let registration = ServerRegistration(
      identity: account.sessionIdentity, installationID: installationID)
    guard serverRegistration != registration else { return }
    do {
      let request = try PushDeviceEndpoint.register(
        baseURL: baseURL, installationID: installationID)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(PushDeviceResponseDTO.self, from: data).checked()
      guard account.sessionIdentity == registration.identity else { return }
      serverRegistration = registration
      registrationError = nil
      debugLog("GOAPI device registration succeeded")
    } catch is CancellationError {
    } catch {
      guard account.sessionIdentity == registration.identity else { return }
      debugLog("GOAPI device registration failed: \(error.localizedDescription)")
      registrationError = "푸시 알림을 서버에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }

  private func unregisterServerDevice(using account: AccountSession) async {
    guard let baseURL = account.apiBaseURL, let installationID else { return }
    do {
      let request = try PushDeviceEndpoint.unregister(
        baseURL: baseURL, installationID: installationID)
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(PushDeviceResponseDTO.self, from: data).checked()
    } catch {
      // FCM 등록도 함께 해제하므로 남은 서버 FID는 다음 실패 발송 때 자동 정리된다.
    }
    serverRegistration = nil
  }

  private func receive(installationID: String?) {
    guard let installationID = installationID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !installationID.isEmpty
    else { return }
    if self.installationID != installationID { serverRegistration = nil }
    self.installationID = installationID
    debugLog("Firebase installation ID received (length: \(installationID.count))")
    Task { await registerServerDeviceIfNeeded() }
  }

  private func didUnregister(installationID: String) {
    if self.installationID == installationID { self.installationID = nil }
    serverRegistration = nil
  }

  private func receive(userInfo: [AnyHashable: Any], opensDestination: Bool = true) {
    guard let destination = RemoteNotificationDestination.make(from: userInfo) else { return }
    receive(destination: destination, opensDestination: opensDestination)
  }

  private func receive(
    destination: RemoteNotificationDestination, opensDestination: Bool = true
  ) {
    latestEvent = RemoteNotificationEvent(destination: destination)
    if opensDestination { self.destination = destination }
  }

  private func debugLog(_ message: String) {
    #if DEBUG
      print("[SENSTA Push] \(message)")
    #endif
  }
}

extension PushNotificationManager: MessagingDelegate {
  nonisolated func messaging(_ messaging: Messaging, didReceiveRegistration installationId: String?) {
    Task { @MainActor in receive(installationID: installationId) }
  }

  nonisolated func messaging(_ messaging: Messaging, didUnregister installationId: String) {
    Task { @MainActor in didUnregister(installationID: installationId) }
  }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // iOS 27 beta에서는 async delegate bridge가 cooperative executor에서 완료되며
    // UIKit의 상태 복원 처리가 메인 스레드 assertion으로 종료될 수 있다.
    let destination = RemoteNotificationDestination.make(
      from: notification.request.content.userInfo)
    if let destination {
      Task { @MainActor [weak self] in
        self?.receive(destination: destination, opensDestination: false)
      }
    }
    completionHandler([.banner, .list, .badge, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let destination = RemoteNotificationDestination.make(
      from: response.notification.request.content.userInfo)
    if let destination {
      Task { @MainActor [weak self] in self?.receive(destination: destination) }
    }
    completionHandler()
  }
}

@MainActor @Observable
private final class RemoteDirectMessagePartnerModel {
  private(set) var partner: DirectMessagePartner?
  private(set) var error: String?
  private(set) var isLoading = false

  func load(userID: Int, account: AccountSession) async {
    guard !isLoading, partner == nil, let baseURL = account.apiBaseURL else { return }
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let request = try PhotographerEndpoint.request(baseURL: baseURL, userID: userID)
      let data = try await account.sendAuthenticated(request)
      let info = try JSONDecoder().decode(PhotographerInfoDTO.self, from: data).checked(
        userID: userID)
      try Task.checkCancellation()
      partner = DirectMessagePartner(
        id: info.uid, name: info.name,
        profileURL: MediaURLResolver.url(for: info.profile, apiBaseURL: baseURL))
    } catch is CancellationError {
    } catch {
      self.error = "사진가 정보를 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}

struct RemoteDirectMessageDestinationView: View {
  let userID: Int
  let account: AccountSession
  let feedService: any PhotoFeedServing
  let detailService: any PhotoPostDetailServing
  @State private var model = RemoteDirectMessagePartnerModel()

  var body: some View {
    Group {
      if let partner = model.partner {
        DirectMessageView(
          partner: partner, account: account, feedService: feedService,
          detailService: detailService)
      } else if let error = model.error {
        ContentUnavailableView {
          Label("대화를 열지 못했어요", systemImage: "wifi.exclamationmark")
        } description: {
          Text(error)
        } actions: {
          Button("다시 시도") { Task { await model.load(userID: userID, account: account) } }
        }
      } else {
        ProgressView("대화를 여는 중…")
      }
    }
    .task { await model.load(userID: userID, account: account) }
  }
}
