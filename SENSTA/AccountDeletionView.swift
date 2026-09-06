import SwiftUI

struct AccountDeletionView: View {
  @Bindable var session: AccountSession
  @State private var confirmation = ""
  @State private var appleNonce: String?
  @State private var isCheckingStatus = false
  @State private var isPreparingApple = false
  @State private var pendingAppleAuthorization: AppleSignInPayload?
  @State private var confirmDeletion = false
  @State private var deleted = false
  @FocusState private var confirmationFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      if deleted {
        Section {
          ContentUnavailableView(
            "계정 삭제 완료", systemImage: "checkmark.circle",
            description: Text("계정과 연결된 데이터가 삭제되었어요."))
          Button("닫기") { dismiss() }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("account-delete-finish")
        }
      } else {
        Section {
          Label("이 작업은 되돌릴 수 없습니다", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
            .foregroundStyle(.red)
          Text("작성한 사진과 게시글, 댓글, 좋아요, 1:1 대화, 알림, 프로필 및 로그인 정보가 영구 삭제됩니다.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Section("삭제 확인") {
          Text("계속하려면 영문 대문자로 DELETE를 입력하세요.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          TextField("DELETE", text: $confirmation)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .fontDesign(.monospaced)
            .focused($confirmationFocused)
            .accessibilityIdentifier("account-delete-confirmation")
        }

        Section {
          deletionControl
          if session.appleLinked == true {
            Text("Apple ID가 연결된 계정은 본인 확인 후 Apple 로그인 승인도 함께 폐기합니다.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let error = session.error {
          Section {
            Label(error, systemImage: "exclamationmark.circle")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("account-delete-error")
          }
        }
      }
    }
    .navigationTitle("계정 삭제")
    .navigationBarTitleDisplayMode(.inline)
    .interactiveDismissDisabled(session.isBusy)
    .confirmationDialog(
      "계정과 데이터를 영구 삭제할까요?", isPresented: $confirmDeletion,
      titleVisibility: .visible
    ) {
      Button("영구 삭제", role: .destructive) { performDeletion() }
      Button("취소", role: .cancel) { pendingAppleAuthorization = nil }
    } message: {
      Text("삭제 후에는 복구할 수 없습니다.")
    }
    .task(id: session.sessionIdentity) { await prepare() }
    .onDisappear {
      confirmation = ""
      pendingAppleAuthorization = nil
      appleNonce = nil
    }
    .senstaScreenStyle()
  }

  @ViewBuilder private var deletionControl: some View {
    if session.appleLinked == true {
      if let appleNonce {
        SENSTAAppleSignInButton(
          nonce: appleNonce, linking: true, isEnabled: canDelete,
          completion: handleAppleAuthorization
        )
        .accessibilityIdentifier("account-delete-apple")
      } else if isPreparingApple {
        ProgressView("Apple 본인 확인 준비 중…")
          .frame(maxWidth: .infinity)
      } else {
        Button("Apple 본인 확인 다시 준비") { Task { await prepareAppleDeletion() } }
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("account-delete-apple-retry")
      }
    } else if session.appleLinked == false {
      Button("계정과 모든 데이터 영구 삭제", role: .destructive) {
        confirmationFocused = false
        confirmDeletion = true
      }
      .disabled(!canDelete)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("account-delete-submit")
    } else if isCheckingStatus {
      ProgressView("계정 연결 상태 확인 중…")
        .frame(maxWidth: .infinity)
    } else {
      Button("계정 연결 상태 다시 확인") { Task { await prepare() } }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("account-delete-status-retry")
    }
  }

  private var canDelete: Bool {
    confirmation == "DELETE" && !session.isBusy
  }

  private func prepare() async {
    guard session.user != nil else { return }
    isCheckingStatus = true
    defer { isCheckingStatus = false }
    await session.loadAppleStatus()
    guard !Task.isCancelled else { return }
    if session.appleLinked == true { await prepareAppleDeletion() }
  }

  private func prepareAppleDeletion() async {
    isPreparingApple = true
    appleNonce = nil
    appleNonce = await session.prepareAppleAccountDeletion()
    isPreparingApple = false
  }

  private func handleAppleAuthorization(_ result: Result<AppleSignInPayload, Error>) {
    switch result {
    case .success(let payload):
      pendingAppleAuthorization = payload
      confirmationFocused = false
      confirmDeletion = true
    case .failure(let error):
      if !SENSTAAppleSignInButton.isCancellation(error) {
        session.reportAppleDeletionAuthorizationFailure()
      }
      Task { await prepareAppleDeletion() }
    }
  }

  private func performDeletion() {
    let nonce = appleNonce
    let payload = pendingAppleAuthorization
    appleNonce = nil
    pendingAppleAuthorization = nil
    Task {
      let succeeded: Bool
      if session.appleLinked == true, let nonce, let payload {
        succeeded = await session.deleteAppleAccount(
          identityToken: payload.identityToken,
          authorizationCode: payload.authorizationCode,
          nonce: nonce, confirmation: confirmation)
      } else if session.appleLinked == false {
        succeeded = await session.deleteAccount(confirmation: confirmation)
      } else {
        succeeded = false
      }
      if succeeded {
        confirmation = ""
        deleted = true
      } else if session.user != nil, session.appleLinked == true {
        await prepareAppleDeletion()
      }
    }
  }
}
