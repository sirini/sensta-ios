# SENSTA iOS 프로젝트 상태

## 현재 목표

- SENSTA Android의 제품 동작과 GOAPI API contract v1을 기준으로 iPhone용 네이티브 SwiftUI 앱을
  개발한다.
- Apple·App Store 등록과 최소 Xcode 프로젝트 기반 위에 공개 피드·게시글 상세와 사진 감상 성능을
  확정하고 제품 소유자 실기기 리뷰를 진행한다.

## 현재 단계

- iOS 17 이상·iPhone 전용 SwiftUI 앱과 unit/UI test target, shared scheme을 만들고 첫 공개 사진 피드를
  구현했다.
- `GET /board/list?id=photo&page=1&option=0&keyword=` 운영 응답을 Android DTO와 대조했다. fixture 기반
  Swift DTO decoding, 오류 envelope, 공개 요청과 차단 목록 필터 회귀 테스트를 갖췄으며, 로딩·빈 상태·
  오류·재시도·당겨서 새로고침을 제공한다.
- 목록 `cover` 상대 경로는 Android와 같이 `t*.webp`에서 `f*.webp` 미리보기로 바꾸고 `sensta.me`의
  HTTPS 절대 URL로 해석한다. 작성자, 앱 포토그래퍼 업적, 제목, 좋아요·댓글·조회수와 날짜를 네이티브
  카드로 표시한다.
- 원격 이미지의 고유 크기와 긴 통계 값이 카드 너비를 넓히지 않도록 이미지 Geometry와 카드 최대 너비를
  분리했다. 피드 카드는 화면 양쪽 12pt 안에 고정하며 UI test로 프레임 좌표를 검증한다.
- 피드 카드를 누르면 익명 `GET /board/view?id=photo&postUid=...&needUpdateHit=0&latestLimit=5` 요청으로
  게시글 상세를 연다. 여러 사진을 가로로 넘기고 각 사진의 EXIF·AI 설명, 본문·태그·첨부 파일 정보·통계와
  시스템 공유를 표시한다. 상세 사진도 화면 양쪽 16pt 안에 고정하는 UI 회귀 테스트를 갖췄다.
- Apple ImageIO가 2400px 고화질 미리보기를 원본·표시 영역 종횡비와 화면 scale에 맞춰 백그라운드에서
  다운샘플링한다. 디코딩 메모리 캐시와 응답 디스크 캐시, 동일 요청 병합·마지막 소비자 취소, 피드 다음
  사진과 상세 앞·뒤 사진 예열을 적용했다. 상세 사진은 손가락 위치를 연속 추적하는 가로 ScrollView
  paging으로 바꿨다.
- macOS 27 beta 환경에서 `/Applications/Xcode-beta.app`의 Xcode 27.0(`27A5252f`), Swift 6.4,
  iOS 27.0 SDK와 시뮬레이터를 확인했다.
- 실제 iPhone은 준비되어 있다.
- 약 10년 전 만료됐던 Apple Developer Program 재가입이 2026-09-04 승인됐다. Team ID는
  `WKPCU58CWL`이며 멤버십은 2027-09-04까지 활성이다. Apple Developer 계약과 App Store Connect
  이용 약관도 동의했다.
- Xcode 라이선스·초기 구성과 Apple Account Team `WKPCU58CWL` 연결을 마쳤다. 실제 iPhone에서 개발자
  모드를 켜고 자동 서명으로 기기 등록, Apple Development 인증서와 `me.sensta.ios.debug` provisioning
  profile 생성, 앱 설치·실행까지 확인했다.
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
- Xcode 27의 iPhone 17 Pro 시뮬레이터에서 Debug test build, Release build와 정적 분석을 통과했다. API
  설정·피드/상세 계약·상태·이미지 파이프라인 unit test 18개와 launch·피드 폭·상세 이동/폭 UI test
  3개가 통과했으며 운영
  데이터 피드로 라이트·다크 모드와 큰 글자 레이아웃을 확인했다.
- iPhone 17 실기기용 Debug 빌드를 Apple Development 인증서와 Team `WKPCU58CWL`로 서명했고,
  공개 피드와 게시글 상세가 포함된 `me.sensta.ios.debug` 설치·실행을 확인했다. 사진 감상 리뷰용 빌드는
  Swift 최적화 `-O`를 임시 적용해 설치했다.

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
- 공개 피드는 로그인 없이 직접 GOAPI를 호출한다. 요청에는 `Authorization`을 붙이지 않으며 서버가 주는
  차단 목록 필터는 Android와 동일하게 적용한다.
- 사진 감상 품질과 스크롤·페이징의 부드러움을 제품 우선순위로 둔다. 저해상도 파일로 바꾸지 않고 표시
  픽셀에 필요한 고화질 데이터를 보존한 채 다운샘플링·캐시·예열로 메모리와 프레임 시간을 관리한다.
- 앱 기능은 fixture와 요청 계약 테스트를 먼저 만든 뒤 작은 수직 기능 단위로 구현·검증한다.

## 선행 조건

- iOS 인증·푸시·앱 출처·HEIC 및 UGC 심사 대응을 위한 GOAPI 사전 작업
- Firebase iOS 앱, Google OAuth iOS client, APNs 인증 키 준비
- App Store 지원 페이지와 개인정보·심사 메타데이터 준비

## 다음 작업

1. 제품 소유자가 실제 iPhone에서 첫/재방문 피드 스크롤과 상세 사진의 느린 드래그·빠른 스와이프·왕복을
   리뷰한다. 승인 뒤 공개 피드 다음 페이지 로딩을 구현한다.
2. Firebase iOS 앱과 APNs 인증 키는 알림 기능 작업이 시작될 때 등록한다.
3. GOAPI의 공용 mobile Google 인증·refresh 경로와 Google ID token 검증 강화를 서버 작업 단위로
   구현하고 보안 회귀 테스트를 추가한다. 이후 Apple 로그인, push, 앱 출처와 업로드 계약을 각각 독립
   작업으로 진행한다.
