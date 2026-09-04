# SENSTA iOS 프로젝트 상태

## 현재 목표

- SENSTA Android의 제품 동작과 GOAPI API contract v1을 기준으로 iPhone용 네이티브 SwiftUI 앱을
  개발한다.
- Apple·App Store 등록과 최소 Xcode 프로젝트 기반을 확정하고 첫 공개 피드 수직 기능을 준비한다.

## 현재 단계

- iOS 17 이상·iPhone 전용 SwiftUI 앱과 unit/UI test target, shared scheme을 생성했다. 앱 기능 구현은
  아직 시작하지 않았다.
- macOS 27 beta 환경에서 `/Applications/Xcode-beta.app`의 Xcode 27.0(`27A5252f`), Swift 6.4,
  iOS 27.0 SDK와 시뮬레이터를 확인했다.
- 실제 iPhone은 준비되어 있다.
- 약 10년 전 만료됐던 Apple Developer Program 재가입이 2026-09-04 승인됐다. Team ID는
  `WKPCU58CWL`이며 멤버십은 2027-09-04까지 활성이다. Apple Developer 계약과 App Store Connect
  이용 약관도 동의했다.
- Xcode 라이선스 동의와 초기 구성은 마쳤고 저장소 환경 점검도 다시 통과했다. 프로젝트에 Team
  `WKPCU58CWL`과 Automatic Signing을 설정했지만 Xcode에 Apple Account가 아직 추가되지 않았다. 연결된
  iPhone과 로컬 Apple Development identity도 없어 실기기 서명은 다음 단계다.
- 계정의 2011년 레거시 기기 3대를 제거하고 연간 등록 슬롯을 초기화했다. 기존 SENSTA App ID나 App
  Store Connect 앱 레코드는 없었다.
- 운영 `me.sensta.ios`와 개발 `me.sensta.ios.debug` App ID를 만들고 Associated Domains, Push
  Notifications, Sign in with Apple capability를 활성화했다.
- App Store Connect에 `SENSTA` 앱(Apple ID `6808687447`, SKU `sensta-ios`)을 생성했다. 가격은 무료,
  배포 국가는 대한민국, 주 카테고리는 사진 및 비디오, 보조 카테고리는 소셜 네트워킹, 출시는 수동으로
  설정했다. 검증 전인 Apple Silicon Mac과 Apple Vision Pro 배포는 껐다. 개인 개발자 계정에 필요한
  대한민국 연락처 및 사업자등록번호 보유 여부 확인도 완료했다.
- Debug는 `me.sensta.ios.debug`, Release는 `me.sensta.ios`를 사용하고 두 구성 모두 운영
  `https://sensta.me/goapi/`를 Info.plist에 주입한다. Associated Domains, Push Notifications와 Sign in
  with Apple entitlement도 App ID 설정과 맞췄다.
- Xcode 27의 iPhone 17 Pro 시뮬레이터에서 Debug·Release 빌드, API 설정 unit test 3개와 초기 화면 UI
  test 1개를 통과했다.

## 결정

- Android 저장소와 분리된 `sirini/sensta-ios` 공개 저장소에서 개발한다.
- SwiftUI와 Swift concurrency를 사용하며 Apple 기본 프레임워크를 우선한다.
- Android와 동일한 백엔드 데이터를 사용하되 iOS 관례에 맞는 사용자 경험을 설계한다.
- 현재 개발에는 Xcode 27 beta를 사용하고, TestFlight·App Store 제출 전 당시 Apple이 허용하는 안정판
  Xcode와 SDK로 다시 검증한다.
- 시스템 전체 Xcode 선택을 강제로 바꾸지 않고 저장소 스크립트가 `DEVELOPER_DIR`를 지정한다.
- 운영 bundle ID는 `me.sensta.ios`, 개발·QA bundle ID는 `me.sensta.ios.debug`로 확정한다.
- 최소 지원 버전은 iOS 17이며 초기 배포 대상은 iPhone이다. iPad는 별도 QA 뒤 확대한다.
- access/refresh token은 Keychain에 저장하고 민감하지 않은 설정만 UserDefaults에 둔다.
- 정확한 GPS 위치는 공개 업로드에 포함하지 않는다.
- 앱 기능 작업은 다음 개발 세션부터 작은 수직 기능 단위로 구현·검증·커밋한다.

## 선행 조건

- Xcode Apple Account에서 Team `WKPCU58CWL`을 연결하고 실제 iPhone 자동 서명을 확인한다.
- iOS 인증·푸시·앱 출처·HEIC 및 UGC 심사 대응을 위한 GOAPI 사전 작업
- Firebase iOS 앱, Google OAuth iOS client, APNs 인증 키 준비
- App Store 지원 페이지와 개인정보·심사 메타데이터 준비

## 다음 작업

1. Xcode Settings의 Accounts에 Apple Account를 추가하고 실제 iPhone을 연결한다. 자동 서명으로 앱을
   실행해 Apple Development 인증서·기기 등록·provisioning 경로를 검증한다.
2. 공개 게시글 목록 응답 fixture와 Swift DTO decoding test를 먼저 만들고, 빈 상태·오류·재시도를 포함한
   첫 사진 피드 수직 기능을 구현한다.
3. Firebase iOS 앱과 APNs 인증 키는 알림 기능 작업이 시작될 때 등록한다.
4. GOAPI의 공용 mobile Google 인증·refresh 경로와 Google ID token 검증 강화를 서버 작업 단위로
   구현하고 보안 회귀 테스트를 추가한다. 이후 Apple 로그인, push, 앱 출처와 업로드 계약을 각각 독립
   작업으로 진행한다.
