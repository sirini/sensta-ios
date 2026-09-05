import SwiftUI

enum EmailSignupValidator {
  static func emailIsValid(_ email: String) -> Bool {
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.range(
      of: #"^[A-Z0-9._%+\-]+@[A-Z0-9\-]+(\.[A-Z0-9\-]+)*\.[A-Z]{2,}$"#,
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  static func passwordIsValid(_ password: String) -> Bool {
    guard password.count >= 8 else { return false }
    var hasLetter = false
    var hasNumber = false
    var hasSpecial = false
    for scalar in password.unicodeScalars {
      if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
      if CharacterSet.letters.contains(scalar) {
        hasLetter = true
      } else if CharacterSet.decimalDigits.contains(scalar) {
        hasNumber = true
      } else {
        hasSpecial = true
      }
    }
    return hasLetter && hasNumber && hasSpecial
  }

  static func message(
    email: String, name: String, password: String, confirmation: String, accepted: Bool
  ) -> String? {
    guard emailIsValid(email) else { return "올바른 이메일 주소를 입력해 주세요." }
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...30).contains(name.count) else { return "이름은 2자 이상 30자 이하로 입력해 주세요." }
    guard passwordIsValid(password) else {
      return "비밀번호는 8자 이상이며 문자, 숫자, 특수문자를 포함하고 공백이 없어야 해요."
    }
    guard password == confirmation else { return "비밀번호가 서로 일치하지 않아요." }
    guard accepted else { return "가입하려면 이용약관과 개인정보 처리방침에 동의해 주세요." }
    return nil
  }
}

struct EmailSignupView: View {
  @Bindable var session: AccountSession
  @Binding var loginEmail: String
  @State private var status: SignupStatus?
  @State private var isLoadingStatus = true
  @State private var isBusy = false
  @State private var email = ""
  @State private var name = ""
  @State private var password = ""
  @State private var confirmation = ""
  @State private var invite = ""
  @State private var verificationCode = ""
  @State private var verificationTarget: Int?
  @State private var completed = false
  @State private var accepted = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  @FocusState private var field: Field?

  private enum Field { case email, name, password, confirmation, invite, verificationCode }

  var body: some View {
    Form {
      if isLoadingStatus {
        Section { ProgressView("가입 가능 여부를 확인하는 중…") }
      } else if completed {
        completionSection
      } else if let availabilityMessage {
        Section {
          ContentUnavailableView(
            "이메일 회원가입을 사용할 수 없어요",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text(availabilityMessage)
          )
          Button("다시 확인") { Task { await loadStatus() } }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("signup-status-retry")
        }
      } else if let verificationTarget {
        verificationSections(target: verificationTarget)
      } else {
        signupSections
      }

      if isBusy {
        Section { ProgressView(verificationTarget == nil ? "인증 메일을 보내는 중…" : "인증 코드를 확인하는 중…") }
      }
      if let error {
        Section {
          Label(error, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(error)
            .accessibilityIdentifier("signup-error")
        }
      }
    }
    .navigationTitle(completed ? "가입 완료" : "회원가입")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadStatus() }
    .onDisappear {
      password = ""
      confirmation = ""
      verificationCode = ""
    }
  }

  @ViewBuilder private var signupSections: some View {
    Section("계정 정보") {
      TextField("이메일", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($field, equals: .email)
        .submitLabel(.next)
        .onSubmit { field = .name }
        .accessibilityIdentifier("signup-email")
      TextField("이름", text: $name)
        .textContentType(.name)
        .focused($field, equals: .name)
        .submitLabel(.next)
        .onSubmit { field = .password }
        .accessibilityIdentifier("signup-name")
    }

    Section("비밀번호") {
      SecureField("비밀번호", text: $password)
        .textContentType(.newPassword)
        .focused($field, equals: .password)
        .submitLabel(.next)
        .onSubmit { field = .confirmation }
        .accessibilityIdentifier("signup-password")
      SecureField("비밀번호 확인", text: $confirmation)
        .textContentType(.newPassword)
        .focused($field, equals: .confirmation)
        .submitLabel(status?.mode == "invite_only" ? .next : .done)
        .onSubmit { field = status?.mode == "invite_only" ? .invite : nil }
        .accessibilityIdentifier("signup-password-confirmation")
      Text("8자 이상, 문자·숫자·특수문자를 포함하고 공백 없이 입력해 주세요.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    if status?.mode == "invite_only" {
      Section("초대") {
        TextField("초대 코드", text: $invite)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($field, equals: .invite)
          .submitLabel(.done)
          .accessibilityIdentifier("signup-invite")
      }
    }

    Section("약관") {
      Button {
        accepted.toggle()
      } label: {
        Label(
          "이용약관과 개인정보 처리방침에 동의합니다",
          systemImage: accepted ? "checkmark.circle.fill" : "circle")
      }
      .foregroundStyle(.primary)
      .accessibilityValue(accepted ? "동의함" : "동의하지 않음")
      .accessibilityIdentifier("signup-policy")
      HStack {
        Link("이용약관", destination: URL(string: "https://sensta.me/terms")!)
        Spacer()
        Link("개인정보 처리방침", destination: URL(string: "https://sensta.me/privacy")!)
      }
      .font(.subheadline)
    }

    Section {
      Button("계정 만들기") { Task { await requestSignup() } }
        .frame(maxWidth: .infinity)
        .disabled(isBusy)
        .accessibilityIdentifier("signup-submit")
    }
  }

  @ViewBuilder private func verificationSections(target: Int) -> some View {
    Section("이메일 인증") {
      Text("\(email.trimmingCharacters(in: .whitespacesAndNewlines))로 보낸 6자리 코드를 입력해 주세요.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      TextField("인증 코드", text: verificationCodeBinding)
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)
        .focused($field, equals: .verificationCode)
        .accessibilityIdentifier("signup-verification-code")
      Button("인증하고 가입 완료") { Task { await verifySignup(target: target) } }
        .frame(maxWidth: .infinity)
        .disabled(isBusy || verificationCode.count != 6)
        .accessibilityIdentifier("signup-verify")
    }
    Section {
      Button("인증 메일 다시 보내기") { Task { await requestSignup() } }
        .disabled(isBusy)
        .accessibilityIdentifier("signup-resend")
      Button("가입 정보 수정") {
        verificationTarget = nil
        verificationCode = ""
        error = nil
      }
      .disabled(isBusy)
      .accessibilityIdentifier("signup-edit")
    }
  }

  private var completionSection: some View {
    Section {
      ContentUnavailableView(
        "SENSTA에 오신 것을 환영해요",
        systemImage: "checkmark.seal.fill",
        description: Text("이제 만든 계정으로 로그인할 수 있어요.")
      )
      Button("로그인으로 돌아가기") {
        loginEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
      }
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("signup-return-to-login")
    }
  }

  private var availabilityMessage: String? {
    guard let status else {
      return isLoadingStatus ? nil : "서버에 연결해 가입 정책을 확인해 주세요."
    }
    if status.mode == "disabled" { return "현재 새 회원가입을 받고 있지 않아요." }
    if status.mode == "verified_email", !status.mailConfigured {
      return "현재 이메일 인증 메일을 보낼 수 없어요. Apple 또는 Google 로그인을 이용해 주세요."
    }
    guard ["verified_email", "invite_only"].contains(status.mode) else {
      return "현재 가입 정책을 앱에서 처리할 수 없어요."
    }
    return nil
  }

  private var verificationCodeBinding: Binding<String> {
    Binding(
      get: { verificationCode },
      set: { verificationCode = String($0.filter(\.isNumber).prefix(6)) })
  }

  private func loadStatus() async {
    guard !isBusy else { return }
    isLoadingStatus = true
    error = nil
    do {
      status = try await session.signupStatus()
    } catch is CancellationError {
      return
    } catch {
      status = nil
    }
    isLoadingStatus = false
  }

  private func requestSignup() async {
    guard !isBusy else { return }
    if let validationError = EmailSignupValidator.message(
      email: email, name: name, password: password, confirmation: confirmation,
      accepted: accepted)
    {
      error = validationError
      return
    }
    if status?.mode == "invite_only", invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      error = "초대 코드를 입력해 주세요."
      return
    }
    field = nil
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      let result = try await session.signup(
        email: email, password: password, name: name, invite: invite)
      if result.completed {
        finishSignup()
      } else if result.requiresVerification, result.target > 0 {
        verificationTarget = result.target
        verificationCode = ""
        field = .verificationCode
      } else {
        error = "회원가입을 계속하지 못했어요. 잠시 뒤 다시 시도해 주세요."
      }
    } catch is CancellationError {
      return
    } catch {
      self.error = signupErrorMessage(error)
    }
  }

  private func verifySignup(target: Int) async {
    guard !isBusy, verificationCode.count == 6 else { return }
    field = nil
    isBusy = true
    error = nil
    defer { isBusy = false }
    do {
      let verified = try await session.verifySignup(
        target: target, code: verificationCode, email: email, password: password, name: name)
      if verified {
        finishSignup()
      } else {
        error = "인증 코드가 올바르지 않거나 만료됐어요. 코드를 확인해 주세요."
      }
    } catch is CancellationError {
      return
    } catch {
      self.error = signupErrorMessage(error)
    }
  }

  private func finishSignup() {
    completed = true
    verificationTarget = nil
    verificationCode = ""
    password = ""
    confirmation = ""
    error = nil
  }

  private func signupErrorMessage(_ error: Error) -> String {
    guard case NuboAPIError.server(let code, _) = error else {
      return "회원가입을 처리하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요."
    }
    switch code {
    case 2, 3:
      return "입력한 가입 정보를 다시 확인해 주세요."
    case 4, 5:
      return "이미 사용 중인 이메일 또는 이름이에요."
    case 9:
      return "현재 인증 메일을 보낼 수 없어요. 잠시 뒤 다시 시도해 주세요."
    case 10:
      return "인증 메일을 이미 보냈어요. 잠시 기다린 뒤 다시 시도해 주세요."
    case 11:
      return "현재 새 회원가입을 받고 있지 않아요."
    case 12:
      return "초대 코드가 올바르지 않거나 만료됐어요."
    default:
      return "회원가입을 처리하지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}
