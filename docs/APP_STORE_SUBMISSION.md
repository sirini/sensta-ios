# SENSTA App Store 제출 가이드

기준일은 2026년 9월 6일이다. Apple 요구 사항은 바뀔 수 있으므로 실제 제출 직전에 연결된 공식 문서를
다시 확인한다.

## 현재 제출 대상

- App Store Connect 앱: `SENSTA`, Apple ID `6808687447`, SKU `sensta-ios`
- bundle ID: `me.sensta.ios`
- 버전: `1.0`, 빌드: `1`
- 지원 범위: iOS 17 이상, iPhone 전용
- 가격·지역: 무료, 대한민국
- 카테고리: 사진 및 비디오 / 소셜 네트워킹
- 출시 방식: 심사 통과 후 수동 출시
- 지원 URL: `https://sensta.me/support`
- 마케팅 URL: `https://sensta.me`
- 개인정보처리방침 URL: `https://sensta.me/privacy`
- 개인정보 선택 사항 URL: `https://sensta.me/delete-account`

지원 URL은 NUBO의 `/support` 페이지로 운영 배포했고 외부 HTTP 200과 실제 이메일 링크를 확인했다.

`SENSTA 1.0 (1)`은 2026년 9월 6일 정식 Xcode 26.6으로 App Store Connect 업로드에 성공했으며 현재
Apple의 빌드 처리와 제출 전 검증을 통과해 App Review에 제출됐다. 상태는 `심사 대기 중`이며 승인을
받아도 자동 공개되지 않는 수동 출시 방식이다. 같은 빌드 번호를 다시 업로드할 수 없으므로 후속 바이너리
수정이 필요하면 빌드 번호를 올린다.

## Apple의 현재 기술 기준

- 2026년 4월 28일부터 App Store Connect 업로드는 Xcode 26 이상과 iOS 26 SDK 이상으로 빌드해야 한다.
- 이 저장소의 제출 기준은 beta가 아닌 `/Applications/Xcode.app`의 Xcode 26.6(`17F113`)이다.
- 앱은 추적하지 않으며 운영체제의 표준 HTTPS 등 면제 암호화만 사용하므로
  `ITSAppUsesNonExemptEncryption`을 `false`로 선언한다.
- 앱의 `UserDefaults` 사용은 Privacy Manifest에 app-only 사유 `CA92.1`로 선언한다.
- Firebase·Google SDK의 privacy manifest와 앱 manifest가 최종 Release 번들에 함께 들어가야 한다.

공식 문서:

- [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

## 제출 빌드 만들기

시스템 전체 Xcode 선택을 바꾸지 않고 정식 Xcode를 현재 셸에서만 사용한다.

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
  -archivePath build/SENSTA-1.0-1.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/SENSTA-1.0-1.xcarchive \
  -exportPath build/AppStoreExport \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

마지막 명령은 서버로 업로드하지 않고 App Store 배포 서명과 IPA 생성을 로컬에서 검증한다. 아카이브 뒤
Xcode의 Window > Organizer에서 `SENSTA 1.0 (1)`을 선택해 Validate App을 먼저 실행하고, 오류가 없을 때
Distribute App > App Store Connect > Upload로 전송한다. 같은 버전에서 다시 업로드해야 하면
`CURRENT_PROJECT_VERSION`을 2 이상으로 올린다.

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
