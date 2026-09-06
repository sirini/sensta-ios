# Firebase와 Apple 서비스 준비

이 문서는 필요한 항목을 기록한 체크리스트이며 자격 증명 자체를 저장하지 않는다.

## 확정 식별자

Apple Developer Program Team `WKPCU58CWL`에 다음 explicit App ID를 만들었다. 두 App ID 모두
Associated Domains, Push Notifications와 Sign in with Apple capability가 활성화되어 있다.

| 용도 | bundle ID | Firebase 앱 |
| --- | --- | --- |
| 운영 | `me.sensta.ios` | SENSTA iOS |
| 개발·QA | `me.sensta.ios.debug` | SENSTA iOS Debug |

개발 앱을 분리하면 운영 앱과 Keychain, 알림 token, Google OAuth 설정과 설치 상태가 섞이지 않는다.

## Firebase iOS 앱

기존 Android 앱과 같은 Firebase 프로젝트에 운영·개발 iOS 앱을 각각 등록한다.

준비 항목:

1. bundle ID와 Firebase 앱을 정확히 일치시킨다.
2. 각 환경의 `GoogleService-Info.plist`를 내려받아 다음 경로에 둔다.
   - 개발·QA: `Config/Firebase/Debug/GoogleService-Info.plist`
   - 운영: `Config/Firebase/Release/GoogleService-Info.plist`
3. 두 파일은 빌드할 때 해당 구성의 앱 번들로 복사되며 Git에는 커밋하지 않는다. 현재 로컬에는 두 파일이
   없으므로 Firebase Console에서 새로 내려받아야 한다.
4. 앱은 Firebase Apple SDK 12.18.0의 `FirebaseCore`와 `FirebaseMessaging`만 직접 연결한다. Analytics는
   추가하지 않는다.
5. Firebase와 Google SDK의 privacy manifest 및 App Privacy 수집 항목을 확인한다.

## APNs와 Firebase Cloud Messaging

Apple Developer 계정이 활성화되면 다음을 준비한다.

1. 운영·개발 App ID의 Push Notifications capability는 이미 활성화돼 있다.
2. Apple Developer의 Keys에서 환경별 APNs 인증 키를 만든다. 현재 Apple key 생성 화면에서는
   `Apple Push Notification service`를 선택하고 `Configure`에서 환경과 범위를 지정한다.
   - 개발: 이름 `SENSTA APNs Sandbox`, 환경 `Sandbox`, 범위 `Topic Specific`, topic
     `me.sensta.ios.debug`
   - 운영: 이름 `SENSTA APNs Production`, 환경 `Production`, 범위 `Topic Specific`, topic
     `me.sensta.ios`
   두 환경을 분리하면 한 키의 노출이나 폐기가 다른 환경에 미치는 영향을 줄이고 Apple의 환경 분리 권고와
   맞는다. `.p8` 파일은 한 번만 내려받을 수 있으므로 안전한 비밀 저장소에 보관하고 각 Key ID를 함께
   기록한다. Team ID는 `WKPCU58CWL`이다.
3. Firebase Console > 프로젝트 설정 > Cloud Messaging에서 환경을 맞춰 업로드한다.
   - `SENSTA iOS Debug`: Development APNs authentication key에 Sandbox `.p8`, Key ID, Team ID
   - `SENSTA iOS`: Production APNs authentication key에 Production `.p8`, Key ID, Team ID
   Firebase는 development·production 키 중 하나 이상을 허용하지만, SENSTA는 실제 QA와 출시를 모두
   검증하므로 두 환경을 각각 구성한다.
4. Xcode target의 Push Notifications capability는 이미 활성화돼 있다. 현재 payload는 사용자에게 보이는
   alert push이므로 silent background fetch용 `remote-notification` Background Mode는 추가하지 않는다.
5. 앱은 알림 화면에서 사용자가 `알림 켜기`를 선택할 때 권한을 요청하고, 허용된 경우에만 APNs와 FCM FID를
   등록한다.
6. GOAPI `b6b9b0f` 이상을 운영에 반영한 뒤 실제 iPhone에서 foreground, background, 종료 상태와 사진·
   1:1 메시지 deep link를 각각 검증한다.

시뮬레이터 테스트만으로 APNs 출시 준비가 완료되었다고 판단하지 않는다.

## Google 로그인

- Google Cloud/Firebase에서 `me.sensta.ios.debug`와 `me.sensta.ios` 각각의 iOS OAuth client를 만들고
  bundle ID를 정확히 연결한다. 이 ID는 iOS 앱 자체를 식별한다.
- `Config/Debug.local.xcconfig.example`을 `Config/Debug.local.xcconfig`로,
  `Config/Release.local.xcconfig.example`을 `Config/Release.local.xcconfig`로 복사하고 각 환경의
  `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID`를 채운다. 두 로컬 파일은 Git이 무시한다.
- GOAPI 인증용 ID token을 받기 위해 기존 Android와 같은 Google Cloud 프로젝트의 Web 유형 server client
  ID를 두 파일의 `GOOGLE_SERVER_CLIENT_ID`로 설정한다. 현재 Android 값은
  `sensta.git/app/src/main/res/values/strings.xml`의 `google_web_client_id`이며, 운영 GOAPI의
  `OAUTH_GOOGLE_ANDROID_CLIENT_ID`와도 같아야 한다. GOAPI가 검증할 audience는 iOS client ID가 아니라
  이 server client ID다.
- 앱은 GoogleSignIn-iOS 9.2.0의 공식 버튼과 인증 흐름을 사용한다. 설정값이 없으면 Google 버튼을
  숨기고 이메일 로그인을 유지한다. `GoogleService-Info.plist`는 향후 Firebase Messaging 연결에
  사용하며 Google 로그인 client ID는 위 로컬 xcconfig가 구성한다.
- Google 로그인과 이메일 로그인이 같은 기존 계정을 안전하게 사용할 수 있는지 테스트한다.
- 앱 로그, crash report와 네트워크 진단에 ID token이 포함되지 않게 한다.

## Sign in with Apple

- Apple App ID와 Xcode target에서 Sign in with Apple capability를 활성화한다.
- SwiftUI의 Apple 제공 로그인 버튼과 AuthenticationServices를 사용한다.
- 요청마다 암호학적으로 안전한 nonce를 만들고 서버가 identity token과 함께 검증한다.
- 사용자의 이름은 최초 승인 때만 받을 수 있으므로 안전하게 전달·저장한다.
- Apple 비공개 이메일과 기존 계정 연결 여부를 사용자에게 명확히 보여준다.
- 계정 삭제와 Apple 자격 증명 취소 시 서버 token 폐기까지 수행한다.

Apple은 이메일이 아니라 Apple의 provider subject를 영구 식별자로 저장한다. 기존 이메일 계정과는
이메일이 같다는 이유만으로 자동 병합하지 않고 로그인된 사용자의 명시적 연결 또는 소유 확인 절차를
사용한다. 이 서버 저장 구조와 연결 API를 먼저 추가한 뒤 앱 버튼을 활성화한다.

## 저장 금지 항목

- APNs `.p8` private key
- Apple client secret 생성용 private key
- signing certificate `.p12`와 비밀번호
- provisioning profile
- Firebase service account JSON
- Google·Apple ID token과 SENSTA access/refresh token

필요한 비밀은 Apple Developer, Firebase Console, 운영 서버 secret 저장소와 로컬 Keychain에만 둔다.
