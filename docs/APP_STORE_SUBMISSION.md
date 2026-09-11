# SENSTA App Store 제출 가이드

기준일은 2026년 9월 11일이다. Apple 요구 사항은 바뀔 수 있으므로 실제 제출 직전에 연결된 공식 문서를
다시 확인한다.

## 현재 제출 대상

- App Store Connect 앱: `SENSTA`, Apple ID `6808687447`, SKU `sensta-ios`
- bundle ID: `me.sensta.ios`
- 버전: `1.0`, 재제출 빌드: `2` (기존 실패 빌드: `1`)
- 지원 범위: iOS 17 이상, iPhone 전용
- 가격·지역: 무료, 대한민국
- 카테고리: 사진 및 비디오 / 소셜 네트워킹
- 출시 방식: 심사 통과 후 수동 출시
- 지원 URL: `https://sensta.me/support`
- 마케팅 URL: `https://sensta.me`
- 개인정보처리방침 URL: `https://sensta.me/privacy`
- 개인정보 선택 사항 URL: `https://sensta.me/delete-account`

지원 URL은 NUBO의 `/support` 페이지로 운영 배포했고 외부 HTTP 200과 실제 이메일 링크를 확인했다.

`SENSTA 1.0 (1)`은 2026년 9월 6일 정식 Xcode 26.6으로 App Store Connect 업로드에 성공했다.
Apple의 초기 빌드 처리와 제출 전 검증을 통과해 App Review에 제출됐지만 이후
`ITMS-90111: Unsupported SDK or Xcode version`으로 실패했다. 9월 11일 App Store Connect에서
`잘못된 바이너리`와 기존 제출의 `해결되지 않은 문제` 상태를 다시 확인했다. 승인 후에는 수동 출시한다.
기존 제출 ID는 `143cfbf7-a31d-4ccd-9d10-e5db7d2f1761`이다.

`1.0 (2)`는 2026-09-11 23:00 KST 업로드에 성공했고 Apple 처리 완료·제출 준비 완료를 확인했다.
기존 스크린샷·메타데이터·심사 정보를 유지하며 빌드 2로 교체한 뒤 23:04 KST 재제출했고 현재
`심사 대기 중`이다. 빌드 ID는 `fc145e89-b43f-4ebb-a6a9-2cdc228d67ad`이며 위 제출 ID를 재사용한다.
재확인 중 자동 출시로 설정된 것을 발견해 기존 결정대로 수동 출시로 저장하고 새로고침 후 유지됨을
확인했다. 승인 후 실제 공개는 별도로 진행한다.

## 빌드 2 검증 결과 (2026-09-11)

- Xcode 27 RC로 iOS 26.5 단위 147개·핵심 UI 7개, iOS 27 RC(`24A434`) 단위 147개·UI 4개 통과.
- Debug test build, Release simulator build, Release archive와 App Store export 통과.
- 최종 아카이브: `build/SENSTA-1.0-2.xcarchive`, 로컬 IPA: `build/AppStoreExport-2/SENSTA.ipa`.
- 아카이브 metadata: `DTXcodeBuild=27A266a`, `DTSDKBuild=24A430`, `BuildMachineOSBuild=26A428`.
- Apple Distribution 서명, production APNs, Apple 로그인·Associated Domains, `get-task-allow=false` 검증.
- 앱과 SDK의 Privacy Manifest 20개는 빌드 1과 동일하며 면제 암호화 선언도 유지한다.
- 로컬 export IPA SHA-256: `9dafaeec018e970d2214b6a503a7eb1743211292e805378da4a9402d93e1ae67`.

## Apple의 현재 기술 기준

- 2026년 4월 28일부터 App Store Connect 업로드는 Xcode 26 이상과 iOS 26 SDK 이상으로 빌드해야 한다.
- Apple은 2026-09-09부터 Xcode 27 RC와 iOS 27 RC SDK의 App Store 제출을 허용한다.
  공식 Xcode 27 RC 빌드는 `27A266a`다.
- 실패한 빌드 1은 Xcode 26.6(`17F113`), iOS 26.5 SDK(`23F81a`), macOS 27 beta 8
  (`26A5425a`) 조합이었다. Xcode 26.6의 공식 지원 호스트는 macOS 26.x까지이므로 이 조합은 피한다.
- 제품 소유자의 업데이트·재시작 후 실제 호스트는 macOS `27.0 (26A428)`로 확인됐다. 업데이트 전
  표시된 `26A5428` 대신 실제 설치 결과를 기준으로 한다.
- 공식 XIP에서 Xcode 27 RC를 `/Applications/Xcode-27-RC.app`에 설치했고 `27A266a`와 iOS 27 SDK,
  Apple 코드 서명을 확인했다. 기존 Xcode 26.6·27 beta 6은 별도로 유지한다.
- `scripts/xcode-release-env.sh`는 RC를 기본으로 선택하며 시스템 Xcode 선택은 변경하지 않는다.
  사전 검사는 정확한 `27A266a`를 요구한다. 새 제출 도구로 변경할 때는 Apple 릴리스 노트를 검증하고
  스크립트의 기준도 갱신한다.
- 앱은 추적하지 않으며 운영체제의 표준 HTTPS 등 면제 암호화만 사용하므로
  `ITSAppUsesNonExemptEncryption`을 `false`로 선언한다.
- 앱의 `UserDefaults` 사용은 Privacy Manifest에 app-only 사유 `CA92.1`로 선언한다.
- Firebase·Google SDK의 privacy manifest와 앱 manifest가 최종 Release 번들에 함께 들어가야 한다.

공식 문서:

- [App Store Connect release notes](https://developer.apple.com/help/app-store-connect/release-notes/)
- [Xcode 27 RC](https://developer.apple.com/news/releases/?id=09092026h)
- [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

## 제출 빌드 만들기

RC 환경에서 아래 명령을 실행한다. Simulator destination은 설치된 runtime과 기기 목록에 맞춘다.

```bash
source ./scripts/xcode-release-env.sh
./scripts/check-release-environment.sh

xcodebuild \
  -project SENSTA.xcodeproj \
  -scheme SENSTA \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  build

xcodebuild \
  -project SENSTA.xcodeproj \
  -scheme SENSTA \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/SENSTA-1.0-2.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/SENSTA-1.0-2.xcarchive \
  -exportPath build/AppStoreExport-2 \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

마지막 명령은 서버로 업로드하지 않고 App Store 배포 서명과 IPA 생성을 로컬에서 검증한다. 아카이브 뒤
Xcode의 Window > Organizer에서 `SENSTA 1.0 (2)`를 선택해 Validate App을 먼저 실행하고, 오류가 없을 때
Distribute App > App Store Connect > Upload로 전송한다. 같은 버전에서 다시 업로드해야 하면
`CURRENT_PROJECT_VERSION`을 아직 사용하지 않은 번호로 올린다.

## App Store 표시 정보 초안

### 이름과 홍보 문구

- 이름: `SENSTA`
- 부제: `사진으로 이어지는 따뜻한 커뮤니티`
- 프로모션 문구: `사진을 온전히 감상하고, 나만의 작품을 편집해 공유하세요. 따뜻한 커뮤니티에서 사진가와 소통할 수 있습니다.`
- 키워드: `사진,포토,사진작가,갤러리,커뮤니티,카메라,작품,해시태그` (UTF-8 79 bytes)
- 저작권: `2026 Heegeun Park`

### 설명

```text
SENSTA는 사진을 온전히 감상하고 작품으로 소통하는 따뜻한 사진 커뮤니티입니다.

• 화면을 가득 채우는 사진 피드와 부드러운 탐색
• 제목, 본문, 사진가, 해시태그와 사진 설명 검색
• 최대 9장의 사진 선택과 자르기, 회전, 반전, 필터 편집
• 사진 정보와 설명, 좋아요, 댓글, 답글과 공유
• 나의 공개·비공개 작품을 모아 보는 작품 스튜디오
• 사진가 프로필, 업적, 1:1 대화와 활동 알림
• 부적절한 콘텐츠 신고와 사용자 차단·해제
• 앱 안에서 직접 실행하는 계정 및 관련 데이터 삭제

업로드 사진은 공개 전에 GPS 위치 정보를 제거합니다. 광고 추적 권한을 요청하지 않으며, 라이트·다크
모드와 큰 글자, VoiceOver, 동작 줄이기를 지원합니다.

SENSTA에서 사진 한 장의 분위기에 조금 더 오래 머물러 보세요.
```

## 스크린샷

6.9형 iPhone 세로 스크린샷 5장을 우선 준비한다. iPhone 17 Pro Max simulator의 1320×2868 PNG는
Apple이 받는 최고 해상도 세트이며 더 작은 iPhone 규격에 재사용할 수 있다. PNG에는 alpha channel이
없어야 하며, 기기 프레임·설명 문구 없이 실제 앱 화면만 제출해도 된다.

권장 순서:

1. 전체 화면 사진 피드
2. 탐색·해시태그 검색
3. 사진 상세와 촬영 정보·설명
4. 업로드 편집·필터·태그
5. 내 작품 스튜디오 또는 1:1 대화

스크린샷에는 테스트용 개인정보, 이메일, 푸시 토큰이나 운영자 전용 정보가 보이지 않아야 한다.

현재 제출 후보 5장은 `build/AppStoreScreenshots/6.9-inch/`에 생성했다. 모두 실제 공개 운영 데이터,
1320×2868, alpha 없는 PNG이며 시각 확인도 마쳤다.

## App Privacy 입력표

앱과 포함 SDK의 선언을 합쳐 입력한다. 모든 항목에서 **추적에 사용**은 `아니요`다.

| 데이터 유형 | 사용자 연결 | 목적 |
| --- | --- | --- |
| 이름 | 예 | 앱 기능 |
| 이메일 주소 | 예 | 앱 기능 |
| 전화번호 | 예 | 앱 기능 |
| 대략적 위치 | 예 | 앱 기능 |
| 사진 또는 비디오 | 예 | 앱 기능 |
| 이메일 또는 문자 메시지 | 예 | 앱 기능 |
| 기타 사용자 콘텐츠 | 예 | 앱 기능 |
| 사용자 ID | 예 | 앱 기능, 분석 |
| 기기 ID | 예 | 앱 기능, 분석 |
| 제품 상호 작용 | 예 | 앱 기능 |
| 기타 사용 데이터 | 예 | 분석 |
| 기타 데이터 유형 | 예 | 앱 기능, 분석 |
| 기타 진단 데이터 | 아니요 | 앱 기능, 분석 |

전화번호·대략적 위치 등은 Google Sign-In SDK manifest가 선언한 항목을 포함한 보수적 답변이다. 정밀
위치, 연락처 주소록, 구매, 금융·건강, 광고 데이터는 수집하지 않는다. App Store Connect에 입력한 뒤
최종 빌드의 privacy report와 다시 대조한다.

## 연령 등급·콘텐츠 권리

- 사용자 생성 콘텐츠: 예
- 메시지 또는 채팅: 예
- 보호자 통제: 아니요
- 연령 확인: 아니요
- 광고: 아니요
- 콘텐츠 권리: 사용자가 업로드한 사진이 있으므로 제3자 콘텐츠를 포함할 수 있음. 이용약관으로 업로드
  권리를 보유한 콘텐츠만 게시하도록 요구하고 신고·차단·운영자 조치를 제공함.

콘텐츠 노출 빈도 질문은 운영 상태를 기준으로 사실대로 답한다. UGC와 1:1 메시지가 있으므로 등급을
임의로 4+로 맞추지 말고 App Store Connect가 계산한 결과를 사용한다.

## App Review 메모 초안

아래의 대괄호 항목만 제출 직전에 실제 심사용 계정으로 바꾼다.

```text
SENSTA is a photo community app. The public photo feed, Explore, search, photo details,
and photographer profiles can be reviewed without signing in.

Demo account
Email: [APP_REVIEW_EMAIL]
Password: [APP_REVIEW_PASSWORD]

After signing in, reviewers can test likes, comments and replies, photo upload/editing,
Studio, achievements, direct messages, notifications, reporting, blocking, and account deletion.

User safety
- Report a photo: open a photo detail, then use the more menu.
- Report or block a user: open another photographer profile or direct conversation, then use the more menu.
- Unblock: use the same profile/conversation menu.

Account deletion
Open Account > Delete Account. The app requires the confirmation word DELETE and a final confirmation.
If Sign in with Apple is linked, the app reauthenticates with Apple and the server revokes the Apple token
before deleting the local account and associated data.

There are no purchases, subscriptions, paid content, or advertisements. Uploaded photos have GPS metadata
removed before transmission. Support: https://sensta.me/support
```

심사용 계정은 실제 이메일 인증이 끝난 복구 가능한 전용 계정이어야 한다. Apple 계정 삭제 재인증까지
보여줘야 할 때는 별도 Apple 테스트 계정을 사용하고 자격 증명을 Review Notes의 안전한 입력란에만 둔다.

## App Store Connect 입력 순서

1. NUBO `/support`를 배포하고 support/privacy/terms/delete-account 네 URL의 외부 HTTP 200을 확인한다.
2. 정식 Xcode로 Release build·test·archive·Validate App을 통과한다.
3. Organizer에서 빌드를 업로드하고 App Store Connect의 처리 완료와 export compliance 상태를 확인한다.
4. 앱 정보의 부제·카테고리·콘텐츠 권리·새 연령 등급 설문을 입력한다.
5. App Privacy를 위 표와 최종 privacy report에 맞춰 저장·게시한다.
6. 버전 페이지에 설명·키워드·지원 URL·스크린샷·빌드를 연결한다.
7. App Review Information에 실제 연락처, 데모 계정과 위 검토 메모를 입력한다.
8. 모든 경고를 해소한 뒤 Add for Review를 누르고, 마지막 확인 화면에서 Submit to App Review를 누른다.
9. 승인 후 자동이 아니라 수동으로 출시한다.
