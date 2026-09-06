import Observation
import SwiftUI

private struct AchievementAcknowledgeBody: Encodable {
  let keys: [String]
}

struct AchievementListResponse: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: [BoardBadgeDTO]?

  func checked() throws -> [BoardBadgeDTO] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
    guard let result, result.count <= 10 else { throw NuboAPIError.malformedResponse }
    var keys = Set<String>()
    for badge in result {
      let key = badge.key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard key == badge.key, !key.isEmpty, key.count <= 80, keys.insert(key).inserted,
        !badge.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        badge.name.count <= 200, badge.description.count <= 2_000,
        !badge.iconKey.isEmpty, badge.iconKey.count <= 80, badge.earnedAt >= 0
      else { throw NuboAPIError.malformedResponse }
    }
    return result
  }
}

struct AchievementAcknowledgeResponse: Decodable {
  let success: Bool
  let error: String?
  let code: Int

  func checked() throws {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: "") }
  }
}

extension AccountEndpoint {
  static func pendingAchievements(baseURL: URL) throws -> URLRequest {
    try request(baseURL: baseURL, path: "auth/user/achievements")
  }

  static func acknowledgeAchievements(baseURL: URL, keys: [String]) throws -> URLRequest {
    let keys = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard (1...10).contains(keys.count), keys.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
      Set(keys).count == keys.count
    else { throw NuboAPIError.invalidRequest }
    var request = try request(
      baseURL: baseURL, path: "auth/user/achievements", method: "PATCH")
    request.httpBody = try JSONEncoder().encode(AchievementAcknowledgeBody(keys: keys))
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }
}

@MainActor @Observable
final class AchievementInbox {
  private(set) var badges: [BoardBadgeDTO] = []
  private(set) var isChecking = false
  private(set) var isAcknowledging = false
  private(set) var acknowledgementMessage: String?
  private var generation = UUID()
  private var snoozedKeys = Set<String>()

  var current: BoardBadgeDTO? { badges.first }

  func reset() {
    generation = UUID()
    badges = []
    isChecking = false
    isAcknowledging = false
    acknowledgementMessage = nil
    snoozedKeys = []
  }

  func check(using account: AccountSession) async {
    guard account.user != nil, let baseURL = account.apiBaseURL, !isChecking,
      !isAcknowledging
    else { return }
    let requestGeneration = generation
    let sessionIdentity = account.sessionIdentity
    isChecking = true
    defer {
      if requestGeneration == generation { isChecking = false }
    }
    do {
      let request = try AccountEndpoint.pendingAchievements(baseURL: baseURL)
      let data = try await account.sendAuthenticated(request)
      let result = try JSONDecoder().decode(AchievementListResponse.self, from: data).checked()
      try Task.checkCancellation()
      guard requestGeneration == generation, sessionIdentity == account.sessionIdentity else {
        return
      }
      badges = result.filter { !snoozedKeys.contains($0.key) }
      acknowledgementMessage = nil
    } catch is CancellationError {
    } catch {
      // 백그라운드 점검 실패는 화면을 가로막지 않고 다음 진입 시 다시 시도한다.
    }
  }

  @discardableResult
  func acknowledgeCurrent(using account: AccountSession) async -> Bool {
    guard let badge = current, account.user != nil, let baseURL = account.apiBaseURL,
      !isChecking, !isAcknowledging
    else { return false }
    let requestGeneration = generation
    let sessionIdentity = account.sessionIdentity
    let key = badge.key
    isAcknowledging = true
    acknowledgementMessage = nil
    defer {
      if requestGeneration == generation { isAcknowledging = false }
    }
    do {
      let request = try AccountEndpoint.acknowledgeAchievements(baseURL: baseURL, keys: [key])
      let data = try await account.sendAuthenticated(request)
      try JSONDecoder().decode(AchievementAcknowledgeResponse.self, from: data).checked()
      try Task.checkCancellation()
      guard requestGeneration == generation, sessionIdentity == account.sessionIdentity,
        current?.key == key
      else { return false }
      badges.removeFirst()
      return true
    } catch is CancellationError {
      return false
    } catch {
      guard requestGeneration == generation, sessionIdentity == account.sessionIdentity else {
        return false
      }
      acknowledgementMessage = "업적 확인을 저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요."
      return false
    }
  }

  func snoozeCurrent() {
    guard acknowledgementMessage != nil, let badge = current else { return }
    snoozedKeys.insert(badge.key)
    badges.removeFirst()
    acknowledgementMessage = nil
  }
}

struct AchievementCelebrationHost: View {
  let account: AccountSession?
  let onViewAchievements: @MainActor () -> Void

  var body: some View {
    if let account, let badge = account.achievements.current {
      AchievementCelebrationCard(
        badge: badge, remainingCount: account.achievements.badges.count, account: account,
        onViewAchievements: onViewAchievements
      )
      .id(badge.key)
      .transition(.opacity)
    }
  }
}

private struct AchievementCelebrationCard: View {
  let badge: BoardBadgeDTO
  let remainingCount: Int
  let account: AccountSession
  let onViewAchievements: @MainActor () -> Void
  @State private var isRevealed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ScaledMetric(relativeTo: .largeTitle) private var badgeSize = 82

  var body: some View {
    ZStack {
      Color.black.opacity(reduceTransparency ? 0.72 : 0.52)
        .ignoresSafeArea()
        .accessibilityHidden(true)
      ScrollView {
        VStack(spacing: 20) {
          ZStack {
            Circle()
              .fill(
                LinearGradient(
                  colors: [.cyan.opacity(0.9), .blue, .indigo],
                  startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.55), lineWidth: 1)
            Image(systemName: badge.symbol)
              .font(.system(size: badgeSize * 0.42, weight: .semibold))
              .foregroundStyle(.white)
            Image(systemName: "sparkles")
              .font(.title2)
              .foregroundStyle(.yellow)
              .offset(x: badgeSize * 0.48, y: -badgeSize * 0.42)
              .accessibilityHidden(true)
          }
          .frame(width: badgeSize, height: badgeSize)
          .shadow(color: .blue.opacity(0.35), radius: 18, y: 8)
          .accessibilityHidden(true)

          VStack(spacing: 8) {
            Text("새로운 업적")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(badge.name.nuboPlainText)
              .font(.title2.weight(.bold))
              .multilineTextAlignment(.center)
              .accessibilityIdentifier("achievement-name")
            Text(badge.description.nuboPlainText)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
            if remainingCount > 1 {
              Text("확인할 새 업적이 \(remainingCount)개 있어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
          }

          if let message = account.achievements.acknowledgementMessage {
            Label(message, systemImage: "wifi.exclamationmark")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("achievement-error")
          }

          VStack(spacing: 10) {
            Button("내 업적 보기", systemImage: "person.text.rectangle") {
              Task {
                if await account.achievements.acknowledgeCurrent(using: account) {
                  onViewAchievements()
                }
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(account.achievements.isChecking || account.achievements.isAcknowledging)
            .accessibilityIdentifier("achievement-view-profile")

            Button {
              Task { await account.achievements.acknowledgeCurrent(using: account) }
            } label: {
              Group {
                if account.achievements.isAcknowledging {
                  ProgressView().tint(SenstaTheme.onPrimary)
                } else {
                  Text(remainingCount > 1 ? "확인하고 다음 업적 보기" : "확인")
                }
              }
              .font(.headline)
              .foregroundStyle(SenstaTheme.onPrimary)
              .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(account.achievements.isChecking || account.achievements.isAcknowledging)
            .accessibilityIdentifier("achievement-confirm")

            if account.achievements.acknowledgementMessage != nil {
              Button("나중에") { account.achievements.snoozeCurrent() }
                .accessibilityIdentifier("achievement-later")
            }
          }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(
          reduceTransparency
            ? AnyShapeStyle(SenstaTheme.surface) : AnyShapeStyle(SenstaTheme.surface.opacity(0.94)),
          in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(.white.opacity(reduceTransparency ? 0.1 : 0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
        .padding(24)
        .scaleEffect(isRevealed || reduceMotion ? 1 : 0.88)
        .opacity(isRevealed ? 1 : 0)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .zIndex(100)
    .task {
      if reduceMotion {
        isRevealed = true
      } else {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
          isRevealed = true
        }
      }
    }
  }
}

extension View {
  func achievementCelebration(
    account: AccountSession?, onViewAchievements: @escaping @MainActor () -> Void
  ) -> some View {
    overlay {
      AchievementCelebrationHost(
        account: account, onViewAchievements: onViewAchievements)
    }
  }
}
