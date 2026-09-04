# SENSTA iOS 프로젝트 상태

## 현재 목표

- SENSTA Android의 제품 동작과 GOAPI API contract v1을 기준으로 iPhone용 네이티브 SwiftUI 앱을
  개발한다.
- 첫 구현 전 Apple, Xcode, GOAPI, Firebase와 App Store 준비사항을 확정한다.

## 현재 단계

- 저장소와 준비 문서만 생성했다. Xcode 프로젝트 및 앱 기능 구현은 아직 시작하지 않았다.
- macOS 27 beta 환경에서 `/Applications/Xcode-beta.app`의 Xcode 27.0(`27A5252f`), Swift 6.4,
  iOS 27.0 SDK와 시뮬레이터를 확인했다.
- 실제 iPhone은 준비되어 있다.
- 약 10년 전 만료됐던 Apple Developer Program 재가입이 2026-09-04 승인됐다. Team ID는
  `WKPCU58CWL`이며 멤버십은 2027-09-04까지 활성이다. Apple Developer 계약과 App Store Connect
  이용 약관도 동의했다.
- Xcode 라이선스 동의와 초기 구성은 마쳤고 저장소 환경 점검도 다시 통과했다. 다만 Xcode의 활성 Team
  연결과 실제 iPhone 자동 서명은 아직 확인하지 않았으며, 로컬 Keychain에도 유효한 Apple Development
  코드서명 identity가 없다.
- 계정의 2011년 레거시 기기 3대를 제거하고 연간 등록 슬롯을 초기화했다. 기존 SENSTA App ID나 App
  Store Connect 앱 레코드는 없었다.
- 운영 `me.sensta.ios`와 개발 `me.sensta.ios.debug` App ID를 만들고 Associated Domains, Push
  Notifications, Sign in with Apple capability를 활성화했다.
- App Store Connect에 `SENSTA` 앱(Apple ID `6808687447`, SKU `sensta-ios`)을 생성했다. 가격은 무료,
  배포 국가는 대한민국, 주 카테고리는 사진 및 비디오, 보조 카테고리는 소셜 네트워킹, 출시는 수동으로
  설정했다. 검증 전인 Apple Silicon Mac과 Apple Vision Pro 배포는 껐다.

## 결정

- Android 저장소와 분리된 `sirini/sensta-ios` 공개 저장소에서 개발한다.
- SwiftUI와 Swift concurrency를 사용하며 Apple 기본 프레임워크를 우선한다.
- Android와 동일한 백엔드 데이터를 사용하되 iOS 관례에 맞는 사용자 경험을 설계한다.
- 현재 개발에는 Xcode 27 beta를 사용하고, TestFlight·App Store 제출 전 당시 Apple이 허용하는 안정판
  Xcode와 SDK로 다시 검증한다.
- 시스템 전체 Xcode 선택을 강제로 바꾸지 않고 저장소 스크립트가 `DEVELOPER_DIR`를 지정한다.
- 운영 bundle ID는 `me.sensta.ios`, 개발·QA bundle ID는 `me.sensta.ios.debug`로 확정한다.
- 초기 배포 대상은 iPhone이다. 최소 지원 iOS 버전과 iPad 대응 여부는 첫 프로젝트 생성 전에 확정한다.
- access/refresh token은 Keychain에 저장하고 민감하지 않은 설정만 UserDefaults에 둔다.
- 정확한 GPS 위치는 공개 업로드에 포함하지 않는다.
- 앱 기능 작업은 다음 개발 세션부터 작은 수직 기능 단위로 구현·검증·커밋한다.

## 선행 조건

- Xcode Apple Account에서 Team `WKPCU58CWL`을 연결하고 실제 iPhone 자동 서명을 확인한다.
- iOS 인증·푸시·앱 출처·HEIC 및 UGC 심사 대응을 위한 GOAPI 사전 작업
- Firebase iOS 앱, Google OAuth iOS client, APNs 인증 키 준비
- App Store 지원 페이지와 개인정보·심사 메타데이터 준비
- 대한민국 배포용 공개 연락처 이메일과 국내 사업자등록번호 보유 여부를 확인해 App Store Connect의
  대한민국 비즈니스 규정 준수 정보를 완료한다.

## 다음 작업

1. Xcode에 Apple Account와 Team `WKPCU58CWL`을 연결한다. 비밀값은 문서나 Git에 기록하지 않는다.
2. 최소 지원 iOS 버전과 초기 iPhone 전용 범위를 확정하고 unit/UI test target을 포함한 최소 SwiftUI
   프로젝트를 만든다. 자동 서명으로 실제 iPhone에서 실행해
   Apple Development 인증서·기기 등록·provisioning 경로를 검증한다.
3. 대한민국 비즈니스 규정 준수 정보, Firebase iOS 앱과 APNs 인증 키는 필요한 실제 정보와 프로젝트가
   준비되는 즉시 등록한다.
4. GOAPI의 공용 mobile Google 인증·refresh 경로와 Google ID token 검증 강화를 첫 서버 작업 단위로
   구현하고 보안 회귀 테스트를 추가한다. 이후 Apple 로그인, push, 앱 출처와 업로드 계약을 각각 독립
   작업으로 진행한다.
