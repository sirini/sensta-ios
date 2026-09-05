import SwiftUI

struct AccountView: View {
  @Bindable var session: AccountSession
  let detailService: any PhotoPostDetailServing
  @State private var email = ""
  @State private var password = ""
  @State private var confirmLogout = false
  @State private var detent: PresentationDetent = .medium
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
            NavigationLink("내 공개 프로필") {
              PhotographerView(
                writer: PhotoPostWriter(
                  id: user.uid, name: user.name, profileURL: session.profileURL, badgeKeys: []),
                service: detailService
              )
              .onAppear { detent = .large }
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
            VStack(alignment: .leading, spacing: 10) {
              Text("다시 만나 반가워요").font(.title2.weight(.semibold))
              Text("SENSTA에서 사용하던 계정으로 로그인하세요.")
                .font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
          }.listRowBackground(Color.clear)
          if googleSignIn.isAvailable {
            Section {
              SENSTAGoogleSignInButton(isEnabled: !session.isBusy) { signinWithGoogle() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Google로 로그인")
            }
            .listRowBackground(rowBackground)

            HStack {
              Rectangle().frame(height: 1).foregroundStyle(.separator)
              Text("또는").font(.caption).foregroundStyle(.secondary)
              Rectangle().frame(height: 1).foregroundStyle(.separator)
            }
            .listRowBackground(Color.clear)
            .accessibilityHidden(true)
          }
          Section("이메일로 로그인") {
            TextField("이메일", text: $email)
              .textContentType(.username).keyboardType(.emailAddress)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($field, equals: .email).submitLabel(.next)
              .onSubmit { field = .password }.accessibilityIdentifier("account-email")
            SecureField("비밀번호", text: $password)
              .textContentType(.password).focused($field, equals: .password).submitLabel(.go)
              .onSubmit { signin() }.accessibilityIdentifier("account-password")
            Button(action: signin) {
              Text("로그인").frame(maxWidth: .infinity)
            }.disabled(!canSignin).accessibilityIdentifier("account-signin")
          }.disabled(session.isBusy).listRowBackground(rowBackground)
        }
        if session.isBusy {
          Section { ProgressView("로그인 정보를 확인하는 중…") }.listRowBackground(rowBackground)
        }
        if let error = session.error {
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
