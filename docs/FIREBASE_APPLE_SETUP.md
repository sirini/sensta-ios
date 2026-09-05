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
2. 각 환경의 `GoogleService-Info.plist`를 내려받는다.
3. 파일은 로컬 Xcode configuration에 연결하되 Git에는 커밋하지 않는다.
4. Analytics가 제품에 필요하지 않다면 Messaging·Installations 중심으로 최소 SDK만 추가한다.
5. Firebase와 Google SDK의 privacy manifest 및 App Privacy 수집 항목을 확인한다.

## APNs와 Firebase Cloud Messaging

Apple Developer 계정이 활성화되면 다음을 준비한다.

1. 운영 App ID에서 Push Notifications capability를 활성화한다.
2. APNs 인증 키를 생성한다. `.p8` 파일, Key ID와 관련 비밀값은 Git에 저장하지 않는다.
3. Firebase Console의 iOS 앱 Cloud Messaging 설정에 APNs 키를 업로드한다.
4. Xcode target에 Push Notifications와 필요한 Background Modes를 추가한다.
5. 알림 권한은 첫 실행 즉시가 아니라 사용자가 가치를 이해할 수 있는 시점에 요청한다.
6. 실제 iPhone에서 foreground, background, 종료 상태와 알림 deep link를 각각 검증한다.

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
