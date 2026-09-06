import AuthenticationServices
import SwiftUI

struct AccountView: View {
  @Bindable var session: AccountSession
  let detailService: any PhotoPostDetailServing
  @State private var email = ""
  @State private var password = ""
  @State private var confirmLogout = false
  @State private var detent: PresentationDetent = .medium
  @State private var appleNonce: String?
  @State private var isPreparingApple = false
  private let googleSignIn = GoogleSignInClient()
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.dismiss) private var dismiss
  @FocusState private var field: Field?
  private enum Field { case email, password }

  var body: some View {
    NavigationStack {
      Form {
        if let user = session.user {
          Section {
            HStack(spacing: 14) {
              AccountAvatar(url: session.profileURL, size: 48)
                .accessibilityIdentifier("account-profile-image")
              VStack(alignment: .leading, spacing: 4) {
                Text(user.name.nuboPlainText).font(.title3.weight(.semibold))
                Text(user.id).font(.subheadline).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 4)
            NavigationLink {
              PhotoStudioView(account: session, publicDetailService: detailService)
                .onAppear { detent = .large }
            } label: {
              Label("내 작품 스튜디오", systemImage: "photo.stack")
            }
            .accessibilityIdentifier("account-photo-studio")
            NavigationLink("내 공개 프로필") {
              PhotographerView(
                writer: PhotoPostWriter(
                  id: user.uid, name: user.name, profileURL: session.profileURL, badgeKeys: []),
                service: detailService
              )
              .onAppear { detent = .large }
            }
          }.listRowBackground(rowBackground)
          Section("Apple 계정") {
            if session.appleLinked == true {
              Label("Apple ID 연결됨", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("account-apple-linked")
            } else if session.appleLinked == false, let appleNonce {
              SENSTAAppleSignInButton(
                nonce: appleNonce, linking: true, isEnabled: !session.isBusy,
                completion: handleAppleAuthorization)
            } else if isPreparingApple {
              ProgressView("연결 상태 확인 중…")
            } else {
              Button("Apple 연결 다시 시도") { Task { await prepareAppleAuthorization() } }
                .accessibilityIdentifier("account-apple-retry")
            }
          }.listRowBackground(rowBackground)
          Section {
            Button("로그아웃", role: .destructive) { confirmLogout = true }
              .disabled(session.isBusy).accessibilityIdentifier("account-logout")
          }.listRowBackground(rowBackground)
        } else if session.needsRestoration {
          Section {
            Text("로그인 상태 확인").font(.headline)
            if !session.isBusy {
              Button("다시 시도") { Task { await session.restore() } }
              Button("이 기기에서 로그아웃", role: .destructive) { Task { await session.logout() } }
            }
          }
        } else {
          Section {
            VStack(spacing: 12) {
              if let appleNonce {
                SENSTAAppleSignInButton(
                  nonce: appleNonce, linking: false, isEnabled: !session.isBusy,
                  completion: handleAppleAuthorization)
              } else if isPreparingApple {
                ProgressView("Apple 로그인 준비 중…")
                  .frame(maxWidth: .infinity, minHeight: 48)
              } else {
                Button("Apple 로그인 다시 시도") { Task { await prepareAppleAuthorization() } }
                  .frame(maxWidth: .infinity, minHeight: 48)
                  .accessibilityIdentifier("account-apple-retry")
              }
              if googleSignIn.isAvailable {
                SENSTAGoogleSignInButton(isEnabled: !session.isBusy) { signinWithGoogle() }
              }
              if let error = session.error {
                Label(error, systemImage: "exclamationmark.circle")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .accessibilityElement(children: .combine)
                  .accessibilityLabel(error)
                  .accessibilityIdentifier("account-error")
              }
              Text("Apple로 처음 로그인하면 새 계정이 만들어져요. 기존 계정은 먼저 로그인한 뒤 Apple ID를 연결하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              HStack {
                Rectangle().frame(height: 1).foregroundStyle(.separator)
                Text("또는").font(.caption).foregroundStyle(.secondary)
                Rectangle().frame(height: 1).foregroundStyle(.separator)
              }
              .accessibilityHidden(true)
            }
          }
          .listRowBackground(Color.clear)
          Section("이메일로 로그인") {
            TextField("이메일", text: $email)
              .textContentType(.username).keyboardType(.emailAddress)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($field, equals: .email).submitLabel(.next)
              .onSubmit { field = .password }.accessibilityIdentifier("account-email")
            SecureField("비밀번호", text: $password)
              .textContentType(.password).focused($field, equals: .password).submitLabel(.go)
              .onSubmit { signin() }.accessibilityIdentifier("account-password")
          }
          .disabled(session.isBusy)
          .listRowBackground(rowBackground)
          Section {
            Button(action: signin) {
              Text("로그인")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.accentColor, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSignin)
            .opacity(canSignin ? 1 : 0.45)
            .accessibilityIdentifier("account-signin")
          }
          .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          Section {
            NavigationLink {
              PasswordResetView(session: session, initialEmail: email)
                .onAppear { detent = .large }
            } label: {
              Label("비밀번호 재설정", systemImage: "key.horizontal")
            }
            .accessibilityIdentifier("account-password-reset")
            NavigationLink {
              EmailSignupView(session: session, loginEmail: $email)
                .onAppear { detent = .large }
            } label: {
              Label("이메일로 회원가입", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("account-email-signup")
          }
          .disabled(session.isBusy)
          .listRowBackground(rowBackground)
        }
        if session.isBusy {
          Section { ProgressView("로그인 정보를 확인하는 중…") }.listRowBackground(rowBackground)
        }
        if let error = session.error, session.user != nil || session.needsRestoration {
          Section { Text(error).font(.subheadline).foregroundStyle(.secondary) }
            .accessibilityIdentifier("account-error").listRowBackground(rowBackground)
        }
      }
      .scrollContentBackground(.hidden)
      .contentMargins(.top, 12, for: .scrollContent)
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationTitle(session.user == nil ? "로그인" : "내 계정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("완료") { dismiss() }.accessibilityIdentifier("account-close")
        }
      }
      .confirmationDialog("로그아웃할까요?", isPresented: $confirmLogout, titleVisibility: .visible) {
        Button("로그아웃", role: .destructive) { Task { await session.logout() } }
      }
      .onDisappear { password = "" }
      .task(id: session.sessionIdentity) { await prepareAppleAuthorization() }
    }
    .presentationDetents(
      dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large], selection: $detent
    )
    .presentationBackground(
      reduceTransparency
        ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.regularMaterial)
    )
    .onChange(of: field) { _, value in
      if value != nil { detent = .large }
    }
    .onChange(of: session.user?.uid) { _, _ in
      detent = dynamicTypeSize.isAccessibilitySize ? .large : .medium
    }
    .onChange(of: dynamicTypeSize, initial: true) { _, size in
      if size.isAccessibilitySize { detent = .large }
    }
  }

  private var rowBackground: Color {
    reduceTransparency ? Color(.secondarySystemGroupedBackground) : Color.primary.opacity(0.045)
  }

  private var canSignin: Bool {
    !session.isBusy && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !password.isEmpty
  }
  private func signin() {
    guard canSignin else { return }
    field = nil
    let secret = password
    password = ""
    Task { await session.signin(email: email, password: secret) }
  }

  private func signinWithGoogle() {
    field = nil
    Task {
      do {
        let token = try await googleSignIn.idToken()
        await session.signinWithGoogle(idToken: token)
      } catch is CancellationError {
      } catch {
        session.reportGoogleSignInFailure()
      }
    }
  }

  private func prepareAppleAuthorization() async {
    isPreparingApple = true
    appleNonce = nil
    let expectedIdentity = session.sessionIdentity
    let preparedNonce: String?
    if session.user != nil {
      await session.loadAppleStatus()
      guard expectedIdentity == session.sessionIdentity, !Task.isCancelled else { return }
      if session.appleLinked == false {
        preparedNonce = await session.prepareAppleAuthorization(linking: true)
      } else {
        preparedNonce = nil
      }
    } else {
      preparedNonce = await session.prepareAppleAuthorization(linking: false)
    }
    guard expectedIdentity == session.sessionIdentity, !Task.isCancelled else { return }
    appleNonce = preparedNonce
    isPreparingApple = false
  }

  private func handleAppleAuthorization(_ result: Result<AppleSignInPayload, Error>) {
    guard let nonce = appleNonce else { return }
    appleNonce = nil
    switch result {
    case .success(let payload):
      let linking = session.user != nil
      Task {
        if linking {
          await session.linkApple(
            identityToken: payload.identityToken, nonce: nonce, name: payload.name)
        } else {
          await session.signinWithApple(
            identityToken: payload.identityToken, nonce: nonce, name: payload.name)
        }
        if session.appleLinked != true { await prepareAppleAuthorization() }
      }
    case .failure(let error):
      if !SENSTAAppleSignInButton.isCancellation(error) {
        session.reportAppleSignInFailure()
      }
      Task { await prepareAppleAuthorization() }
    }
  }
}

struct AccountAvatar: View {
  let url: URL?
  let size: CGFloat

  var body: some View {
    CachedAsyncPhotoImage(url: url, targetSize: CGSize(width: size, height: size)) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFill()
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable().scaledToFit().foregroundStyle(.secondary)
          .background(Color(.tertiarySystemBackground))
      }
    }
    .frame(width: size, height: size).clipShape(Circle())
    .accessibilityLabel("내 프로필 사진")
  }
}

struct AppleSignInPayload: Equatable, Sendable {
  let identityToken: String
  let name: String
}

struct SENSTAAppleSignInButton: View {
  let nonce: String
  let linking: Bool
  let isEnabled: Bool
  let completion: @MainActor (Result<AppleSignInPayload, Error>) -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-test-apple") {
        Button {
          completion(
            .success(
              AppleSignInPayload(
                identityToken: "ui-test-apple-id-token", name: "Apple 사진가")))
        } label: {
          Label(linking ? "Apple로 계속하기" : "Apple로 로그인", systemImage: "apple.logo")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .background(colorScheme == .dark ? .white : .black, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("account-apple-signin")
      } else {
        nativeButton
      }
    #else
      nativeButton
    #endif
  }

  private var nativeButton: some View {
    SignInWithAppleButton(
      linking ? .continue : .signIn,
      onRequest: { request in
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce
      },
      onCompletion: { result in
        switch result {
        case .success(let authorization):
          do { completion(.success(try Self.payload(from: authorization))) } catch {
            completion(.failure(error))
          }
        case .failure(let error):
          completion(.failure(error))
        }
      }
    )
    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
    .clipShape(Capsule())
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityIdentifier("account-apple-signin")
  }

  static func isCancellation(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == ASAuthorizationError.errorDomain
      && error.code == ASAuthorizationError.Code.canceled.rawValue
  }

  private static func payload(from authorization: ASAuthorization) throws -> AppleSignInPayload {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let tokenData = credential.identityToken,
      let identityToken = String(data: tokenData, encoding: .utf8), !identityToken.isEmpty
    else { throw NuboAPIError.invalidResponse }
    let name =
      credential.fullName.map {
        PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
      } ?? ""
    return AppleSignInPayload(identityToken: identityToken, name: name)
  }
}
