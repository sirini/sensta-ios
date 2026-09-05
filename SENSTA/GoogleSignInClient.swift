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

struct SENSTAGoogleSignInButton: UIViewRepresentable {
  let isEnabled: Bool
  let action: @MainActor () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(action: action) }

  func makeUIView(context: Context) -> SENSTAGoogleButtonControl {
    let control = SENSTAGoogleButtonControl()
    control.accessibilityIdentifier = "account-google-signin"
    control.addTarget(context.coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
    return control
  }

  func updateUIView(_ control: SENSTAGoogleButtonControl, context: Context) {
    control.isEnabled = isEnabled
    control.signInButton.isEnabled = isEnabled
  }

  @MainActor
  final class Coordinator: NSObject {
    let action: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func invoke() { action() }
  }
}

final class SENSTAGoogleButtonControl: UIControl {
  let signInButton = GIDSignInButton()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityLabel = "Google로 로그인"
    signInButton.style = .wide
    signInButton.isUserInteractionEnabled = false
    signInButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(signInButton)
    NSLayoutConstraint.activate([
      signInButton.centerXAnchor.constraint(equalTo: centerXAnchor),
      signInButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      signInButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
      signInButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: CGSize {
    CGSize(width: signInButton.intrinsicContentSize.width, height: 48)
  }
}
