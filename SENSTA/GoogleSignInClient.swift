import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

@MainActor
struct GoogleSignInClient {
  private let configuration: GIDConfiguration?

  init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
    func configuredValue(_ key: String) -> String? {
      guard let rawValue = info[key] as? String else { return nil }
      let configured = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !configured.isEmpty, !configured.contains("$(") else { return nil }
      return configured
    }
    if let clientID = configuredValue("GIDClientID"),
      let serverClientID = configuredValue("GIDServerClientID")
    {
      // serverClientID는 Android와 같은 GOAPI audience여야 서버 계정 계약을 공유한다.
      configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
    } else {
      configuration = nil
    }
  }

  var isAvailable: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-test-google") { return true }
    #endif
    return configuration != nil
  }

  func idToken() async throws -> String {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-test-google") {
        return "ui-test-google-id-token"
      }
    #endif
    guard let configuration,
      let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    else { throw NuboAPIError.configuration }
    GIDSignIn.sharedInstance.configuration = configuration
    let result: GIDSignInResult
    do {
      result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: Self.presentingViewController(from: root))
    } catch let error as NSError
      where error.domain == kGIDSignInErrorDomain
        // Objective-C의 kGIDSignInErrorCodeCanceled는 Swift에서 타입 이름 없이 -5로 노출된다.
        && error.code == -5
    {
      throw CancellationError()
    }
    guard let token = result.user.idToken?.tokenString, !token.isEmpty else {
      throw NuboAPIError.invalidResponse
    }
    return token
  }

  static func handle(_ url: URL) -> Bool {
    GIDSignIn.sharedInstance.handle(url)
  }

  private static func presentingViewController(from root: UIViewController) -> UIViewController {
    if let presented = root.presentedViewController {
      return presentingViewController(from: presented)
    }
    if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
      return presentingViewController(from: visible)
    }
    if let tabs = root as? UITabBarController, let selected = tabs.selectedViewController {
      return presentingViewController(from: selected)
    }
    return root
  }
}

struct SENSTAGoogleSignInButton: View {
  let isEnabled: Bool
  let action: @MainActor () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 0) {
        // Google 원본 로고의 크기와 iOS용 앞 16pt, 뒤 12pt 여백을 유지한다.
        Image("GoogleSignInMark")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .accessibilityHidden(true)
        Spacer().frame(width: 12)
        Text("Google로 로그인")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(textColor)
        Spacer(minLength: 16)
      }
      .padding(.leading, 16)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(fillColor, in: Capsule())
      .overlay {
        Capsule().strokeBorder(strokeColor, lineWidth: colorScheme == .dark ? 1 : 0)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityIdentifier("account-google-signin")
    .accessibilityLabel("Google로 로그인")
  }

  private var fillColor: Color {
    colorScheme == .dark
      ? Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255)
      : Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
  }

  private var strokeColor: Color {
    Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255)
  }

  private var textColor: Color {
    colorScheme == .dark
      ? Color(red: 227 / 255, green: 227 / 255, blue: 227 / 255)
      : Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
  }
}
