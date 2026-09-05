# SENSTA iOS 프로젝트 상태

## 현재 목표

- SENSTA Android의 제품 동작과 GOAPI API contract v1을 기준으로 iPhone용 네이티브 SwiftUI 앱을
  개발한다.
- Apple·App Store 등록과 최소 Xcode 프로젝트 기반 위에 공개 피드·게시글 상세와 사진 감상 성능을
  유지하며 공개 피드 페이지 추가 로딩과 오류 복구를 안정화한다.

## 현재 단계

- iOS 17 이상·iPhone 전용 SwiftUI 앱과 unit/UI test target, shared scheme을 만들고 첫 공개 사진 피드를
  구현했다.
- `GET /board/list?id=photo&page=1&option=0&keyword=` 운영 응답을 Android DTO와 대조했다. fixture 기반
  Swift DTO decoding, 오류 envelope, 공개 요청과 차단 목록 필터 회귀 테스트를 갖췄으며, 로딩·빈 상태·
  오류·재시도·당겨서 새로고침을 제공한다.
- 목록 `cover` 상대 경로는 Android와 같이 `t*.webp`에서 `f*.webp` 미리보기로 바꾸고 `sensta.me`의
  HTTPS 절대 URL로 해석한다. 작성자, 앱 포토그래퍼 업적, 제목, 좋아요·댓글·조회수와 날짜를 네이티브
  오버레이로 표시한다.
- Android의 대표 피드 정체성을 이어받아 사진 한 장이 노치·홈 인디케이터 영역을 포함한 화면 전체를
  채우고 세로 페이지 단위로 스냅되도록 구성했다. 좌상단 워드마크는 Android가 사용하는 Oleo Script
  Bold 원본의 `SENSTA` 글자 윤곽·크기·배치·투명도를 그대로 옮긴 벡터이며, 하단 그라데이션 위에는
  작성자·제목·통계를 배치한다. UI test가 카드의 화면 네 변과 워드마크 이미지 노출을 검증한다.
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
  설정·피드/상세 계약·상태·이미지 파이프라인 unit test 18개와 launch·전체 화면 피드·상세 이동/폭 UI test
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
- Android와 공유하는 Oleo Script Bold 워드마크는 글꼴 파일을 런타임에 중복 탑재하지 않고 동일 glyph
  outline의 벡터 asset으로 유지하며 SIL Open Font License를 저장소에 보존한다.
- 앱 기능은 fixture와 요청 계약 테스트를 먼저 만든 뒤 작은 수직 기능 단위로 구현·검증한다.

## 선행 조건

- iOS 인증·푸시·앱 출처·HEIC 및 UGC 심사 대응을 위한 GOAPI 사전 작업
- Firebase iOS 앱, Google OAuth iOS client, APNs 인증 키 준비
- App Store 지원 페이지와 개인정보·심사 메타데이터 준비

## 2026-09-05 리뷰와 오늘 작업

- 새벽 마지막 커밋 `641b733`까지 공개 피드·상세·이미지 파이프라인과 Android/GOAPI 계약을 리뷰했다.
- 요청 취소가 `URLError.cancelled`로 전달되면 일반 통신 오류로 바뀌던 문제를 수정했다. 취소된 응답은
  피드·상세 상태에 반영하지 않는다.
- 새로고침 실패 시 기존 사진 목록을 유지하고 별도 오류 안내·재시도를 제공한다.
- 첫 수정은 단위 테스트 21개·UI 테스트 3개와 Debug test build·Release simulator build를 통과했다.
- 공개 피드 마지막 세 장에 가까워지면 다음 페이지를 불러온다. GOAPI의 `rowCount - notices.count`와
  필터 전 글 수·전체 글 수로 종료를 판단하고, 중복 ID를 제거하며 차단/중복만 있는 페이지를 건너뛴다.
- 추가 로딩 실패는 현재 사진과 위치를 유지한 채 마지막 사진 위에서 수동 재시도를 제공한다. 새로고침은
  진행 중인 추가 요청을 취소하며 이전 응답이 새 목록에 섞이지 않도록 요청 세대를 구분한다.
- 제품 소유자가 어제 최종 실기기 빌드에서 버벅임·멈칫함 없이 부드럽게 사진 감상에 집중할 수 있었고,
  Android 대비 세련된 디자인에도 만족한다고 확인했다. 기존 감상 경험을 후속 기능의 기준으로 유지한다.
- 최종 단위 테스트 27개·UI 테스트 4개와 Debug test build·Release simulator build를 통과했다.
  Debug 전용 고정 데이터로 페이지 추가 실패·재시도·기존 위치 유지·다음 페이지 스와이프를 검증한다.
- 오늘의 복구 수정·페이지 로딩·자동 검증은 완료했다. 로그인은 공용 mobile 인증 계약 정리가 선행되는
  다음 독립 작업이다. 오늘 변경분의 실기기 QA는 아직 수행하지 않았다.

## iOS 우선 후속 개발

- 제품 소유자 요청에 따라 서버 변경 없이 가능한 iOS 작업을 먼저 진행한다. Android 운영 API의 경로·
  요청·응답을 유지하고 인증·푸시 서버 변경은 필요한 시점에 최소 범위로 별도 검증한다.
- 첫 피드는 기존 정체성을 유지한다. 나머지 화면은 사진 전체 구도·여백·절제된 정보 배치와 iOS 기본
  조작을 우선한다.
- 상세 사진을 잘라 채우는 방식에서 전체 구도 표시로 바꾸고, 검은 배경의 전체 화면 감상·핀치/두 번 탭
  확대·사진 넘기기·닫기를 추가했다. VoiceOver 확대 액션과 동작 줄이기도 지원한다.
- 상세 촬영 정보·설명을 처음에는 독립적으로 배치했으나 제품 소유자 피드백에 따라 Android와 같은
  단일 패널 구조로 개선했다. 상단은 간결한 EXIF 요약, 하단은 AI 설명이며 시스템의 라이트/다크 색을 따른다. 단위 28개·UI 5개와 Debug/Release
  빌드를 통과했고, 테스트 캡처에서 상세와 전체 화면 배치를 확인했다. 확대 감상의 실기기 QA는 남아 있다.
- 댓글은 상세 본문 아래에서 스와이프로 바로 읽는다. 우상단 버튼은 댓글 위치로 이동하며, 기존
  `GET /comment/list`를 익명 호출한다. 상세 응답의 게시판 UID를 사용하고
  공개 댓글·답글·좋아요 수·날짜, 더 보기와 오류 재시도를 표시한다. 비공개/알 수 없는 status는 표시하지
  않으며 게시판·게시글 불일치 응답도 거부한다.
- 댓글 포함 최종 단위 36개·UI 6개와 Debug/Release 빌드가 통과했다. 운영 댓글 API의 success 응답과
  스크린샷 배치를 확인했다. 기존과 같은 임시 Swift `-O` 설정의 서명 Debug 빌드를 연결된 iPhone 17에
  설치·실행했다. 핀치·상세 왕복·댓글의 실기기 제품 QA는 제품 소유자가 진행한다.
- GOAPI·Android 코드는 변경하지 않았다. 서버 업데이트·재시작과 Firebase 설정은 이번 작업에 필요 없다.

- EXIF/AI 테마 패널과 본문 아래 댓글 배치를 추가 검증했다. 단위 36개·라이트/다크/큰 글자 UI와 댓글
  스와이프·페이지 추가·재시도, Debug/Release 빌드가 통과했고 캡처에서 패널 배치를 확인했다.

- 공개 제목 검색은 검색어별 목록 상태와 추가 페이지·빈 결과·재시도·새로고침을 제공한다. 사진 격자는
  기본 2열, 접근성 큰 글자에서 1열이다. 서버의 추가 QueryUnescape에 맞춰 한글·특수문자 검색어를
  인코딩하며 운영 `커피` 검색과 `% + &` 검색의 success 응답을 확인했다.

- 검색 포함 최종 단위 37개·UI 8개와 Debug/Release 빌드가 통과했다. 검색 격자·상세 이동과 EXIF/AI
  라이트/다크/큰 글자 캡처를 확인했다. 최종 서명 Debug 앱은 기존 감상 QA와 같은 Swift `-O` 설정으로
  빌드했다.

## 다음 작업

1. iPhone에 설치한 새 빌드에서 상세 사진 탭 → 확대/축소·가로 넘기기·닫기와 우상단 댓글 버튼을 확인한다.
2. 탐색 디자인·검색의 실기기 동작은 제품 소유자가 승인했다. 사진가 화면을 추가했으며 상세 작성자 → 최근 작품 → 상세 왕복을 확인한다.
3. 로그인 단계에서 iOS Google client와 Keychain 세션을 준비한다. 기존 `/auth/android/google`·refresh는
   플랫폼 식별 검사가 없어 같은 token audience·body 계약으로 재사용 가능하며, 범용 경로 별칭은 필수가
   아니다. 실제 iOS token 발급·기존 Android 회귀 검증은 아직 남아 있다.
4. Apple 로그인·계정 연결/삭제와 push는 필요한 서버 계약 및 당시 심사 규정을 별도 검토한다. Firebase·
   OAuth·APNs 설정이 필요할 때 제품 소유자가 브라우저에서 처리할 항목을 구체적으로 안내한다.

## 탐색과 다중 검색 (2026-09-05)

- 탐색 진입 시 최근 사진을 2열 그리드로 표시하며 접근성 큰 글자에서는 1열로 전환한다.
- 기본 검색은 저장된 AI 설명(option=12), 나머지는 제목(0)·본문(1)·닉네임(2)·해시태그(3)다.
  기존 Android/GOAPI 계약을 그대로 사용하며 새 OpenAI 호출이나 의미 기반 검색을 추가하지 않는다.
- 최근 태그는 목록 응답의 config.uid로 `/board/tag/recent`를 호출한다. 태그 선택 즉시 검색하며
  태그 오류는 사진 그리드를 가리지 않고 따로 재시도한다. 검색어를 지우면 최근 사진으로 돌아간다.
- 닉네임 검색은 기존 서버의 부분 일치 사용자 한 명 선택 규칙을 따른다. 여러 사진가 통합 검색으로
  확장하지 않았으며 정확한 닉네임을 권장한다. 서버·Android 변경 및 운영 재시작은 필요 없다.
- 단위 테스트 41개·UI 테스트 9개와 Debug/Release 빌드가 통과했다. 운영 API의 5개 검색 옵션과 최근
  태그 success 응답, 테스트 캡처의 그리드·태그·선택 상태를 확인했다. 기존 Swift `-O` 서명 빌드로
  iPhone 17 설치를 완료했으며 기기 잠금으로 자동 실행은 하지 못했다. 실기기 제품 QA는 남아 있다.

## 사진가 화면 (2026-09-05)

- 제품 소유자가 탐색의 정갈한 디자인과 사진 중심 동작을 승인했다. 다음 단계로 공개 사진가 화면을 추가했다.
- 상세 작성자 영역을 누르면 프로필 사진·닉네임·소개와 최근 작품 그리드를 표시한다. 작품을 누르면 상세로
  이동하며 돌아왔을 때 프로필을 다시 요청하지 않는다. 큰 글자는 1열, 기본은 2열이다.
- 기존 `/auth/user/info?targetUserUid=...`와 `/board/user/latest?targetUserUid=...&limit=12`를 익명으로
  사용한다. 최근 활동 12건 중 photo 게시판만 포함하므로 전체 작품 페이지네이션은 아직 제공하지 않는다.
- 활동 응답에는 썸네일이 없어 기존 상세 API를 최대 3건씩 병렬 호출한다. 공개 접근 검사와 게시글·작성자
  UID 대조를 통과한 작품만 표시하며 일부 실패 시 성공한 작품을 유지하고 재시도한다. 차단된 프로필과
  요청 UID가 다른 프로필은 표시하지 않는다. 새로고침 실패도 기존 프로필·작품을 유지한다.
- GOAPI·Android 변경과 Firebase 설정은 필요 없다. UID 기반 전체 작품 목록 API는 이후 서버 작업으로 남긴다.
- 단위 46개와 기존 UI 9개를 통과했다. 새 사진가 UI 테스트에서 작성자 행의 빈 영역 터치 누락을 발견해
  contentShape로 수정했으며 재실행에서 오류 재시도·작품 상세 진입·뒤로 가기를 통과했다. Debug/Release
  빌드와 프로필 캡처를 확인하고 수정된 Swift `-O` 서명 앱을 iPhone 17에 설치·실행했다.

## 공개 업적·활동 통계 (2026-09-05)

- 공개 프로필 응답의 업적 전체를 카드로 표시하고, 선택 시 이름·설명·획득일을 시트로 보여준다.
  임의 등급·순위를 만들지 않고 실제 획득 업적만 사용한다.
- 프로필 아래에 작품·사진·받은 좋아요를 집계한다. Android 본인 스튜디오의 집계식을 재사용하되 다른
  사용자에게는 공개 작품만 포함한다. 비공개·삭제 작품은 제외하므로 본인 통계와 다를 수 있다.
- 기존 서버에는 공개 통계가 없어 GOAPI `934d836`에 `/board/user/summary`를 추가했다. 기존 Android
  인증 API와 스키마는 유지한다. Go 전체 테스트·vet, 권한/UID/차단/공개 상태 회귀 테스트가 통과했다.
- 서버 업데이트 전 또는 통계 오류 시 `—`와 재시도를 표시하고 업적·최근 작품은 유지한다. 통계에
  최근 12개 작품의 일부 합계를 사용하지 않는다.
- 운영자는 GOAPI 저장소 최신 main을 받고 기존 배포 방식으로 재빌드·재시작한다. DB 마이그레이션은 없다.
  `https://sensta.me/goapi/board/user/summary?id=photo&targetUserUid=1`의 success=true로 확인한다.
- iOS 단위 48개·UI 10개와 Debug/Release 빌드가 통과했다. 업적 상세·통계 수치·작품 왕복 캡처를 확인했다.
  서명 Debug 앱을 iPhone 17에 설치했으며 기기 잠금으로 자동 실행은 되지 않았다. 운영 통계 확인은 서버
  업데이트 후 진행한다. 다음 단계는 로그인 기반 좋아요·댓글 참여 흐름이다.
