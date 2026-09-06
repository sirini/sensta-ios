import SwiftUI

struct PasswordResetView: View {
  @Bindable var session: AccountSession
  @State private var email: String
  @State private var isBusy = false
  @State private var requested = false
  @State private var error: String?
  @FocusState private var emailFocused: Bool

  init(session: AccountSession, initialEmail: String) {
    self.session = session
    _email = State(initialValue: initialEmail.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  var body: some View {
    Form {
      if requested {
        Section {
          VStack(spacing: 12) {
            Image(systemName: "envelope.badge")
              .font(.system(size: 36))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            Text("메일을 확인해 주세요")
              .font(.headline)
            Text(
              "입력한 주소가 SENSTA 계정에 등록되어 있다면 비밀번호 재설정 링크를 보냈어요. 링크는 10분 동안 한 번만 사용할 수 있어요."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 18)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            "메일을 확인해 주세요. 입력한 주소가 SENSTA 계정에 등록되어 있다면 비밀번호 재설정 링크를 보냈어요. 링크는 10분 동안 한 번만 사용할 수 있어요."
          )
          .accessibilityIdentifier("password-reset-complete")
        }
        Section {
          Button("다른 이메일 사용") {
            requested = false
            error = nil
            emailFocused = true
          }
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("password-reset-edit")
        }
      } else {
        Section("계정 이메일") {
          TextField("이메일", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($emailFocused)
            .submitLabel(.send)
            .onSubmit { Task { await requestReset() } }
            .disabled(isBusy)
            .accessibilityIdentifier("password-reset-email")
          Text("가입할 때 사용한 이메일로 재설정 링크를 보내드려요.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Section {
          Button("재설정 메일 보내기") { Task { await requestReset() } }
            .frame(maxWidth: .infinity)
            .disabled(isBusy)
            .accessibilityIdentifier("password-reset-submit")
        }
      }

      if isBusy {
        Section { ProgressView("재설정 메일을 요청하는 중…") }
      }
      if let error {
        Section {
          Label(error, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(error)
            .accessibilityIdentifier("password-reset-error")
        }
      }
    }
    .navigationTitle("비밀번호 재설정")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func requestReset() async {
    guard !isBusy else { return }
    guard EmailSignupValidator.emailIsValid(email) else {
      error = "올바른 이메일 주소를 입력해 주세요."
      return
    }
    emailFocused = false
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      try await session.requestPasswordReset(email: email)
      requested = true
    } catch is CancellationError {
      return
    } catch NuboAPIError.server(let code, _) where code == 9 {
      self.error = "현재 재설정 메일을 보낼 수 없어요. 잠시 뒤 다시 시도해 주세요."
    } catch {
      self.error = "재설정 메일을 요청하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요."
    }
  }
}
