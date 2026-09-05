import SwiftUI

struct AccountView: View {
  @Bindable var session: AccountSession
  let detailService: any PhotoPostDetailServing
  @State private var email = ""
  @State private var password = ""
  @State private var confirmLogout = false
  @Environment(\.dismiss) private var dismiss
  @FocusState private var field: Field?
  private enum Field { case email, password }

  var body: some View {
    NavigationStack {
      Form {
        if let user = session.user {
          Section {
            Label(user.name.nuboPlainText, systemImage: "person.crop.circle")
              .font(.title3.weight(.semibold))
            Text(user.id).foregroundStyle(.secondary)
            NavigationLink("내 공개 프로필") {
              PhotographerView(
                writer: PhotoPostWriter(
                  id: user.uid, name: user.name, profileURL: nil, badgeKeys: []),
                service: detailService)
            }
          }
          Section {
            Button("로그아웃", role: .destructive) { confirmLogout = true }
              .disabled(session.isBusy).accessibilityIdentifier("account-logout")
          }
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
              Image(systemName: "camera.aperture").font(.largeTitle).accessibilityHidden(true)
              Text("다시 만나 반가워요").font(.title2.weight(.semibold))
              Text("SENSTA에서 사용하던 계정으로 로그인하세요.")
                .font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
          }.listRowBackground(Color.clear)
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
          }.disabled(session.isBusy)
        }
        if session.isBusy {
          Section { ProgressView("로그인 정보를 확인하는 중…") }
        }
        if let error = session.error {
          Section { Text(error).font(.subheadline).foregroundStyle(.secondary) }
            .accessibilityIdentifier("account-error")
        }
      }
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
}
