# Guideline 2.1 추가 자료 대응

2026-09-12 08:56 KST Apple 메시지, SENSTA 1.0 (2), 제출 ID
`143cfbf7-a31d-4ccd-9d10-e5db7d2f1761` 기준이다. 이번 메시지는 제한된 심사 이력에 따른 추가 정보
요청이며 구체적인 충돌이나 기능 결함은 지적하지 않았다. 현재 재심사 제출은 하지 않았다.

## 준비 상태

- 앱 목적·대상, 사용 방법, 외부 서비스, 지역 차이, 콘텐츠 권리 설명을 준비하고 App Store Connect
  Review Notes에 기존 삭제 계정 안내와 함께 3,697자로 저장했다. 영상은 준비 중이라고 명시했다.
- 기존 App Store Connect의 기본 심사 계정과 삭제 테스트 계정 안내는 유지한다. 실제 자격 증명은
  이 문서나 Git에 복사하지 않는다.
- 제품 소유자가 실제 iPhone 영상을 직접 촬영하기로 했다. 영상, 기기 모델, iOS 버전, 빌드 확인은 대기 중이다.
- 영상 검토 뒤 Reply와 Review Notes 양쪽에 동일한 자료를 제공한다. 촬영하지 않은 기능이나
  확인하지 않은 OS/기기에서 성공했다고 기재하지 않는다.
- 코드 변경이나 새 바이너리가 필요하다는 근거는 현재 없다. 영상 QA에서 결함이 발견되면 별도 수정한다.

## 촬영 순서

실제 iPhone에서 TestFlight의 제출 빌드 **1.0 (2)** 를 사용한다. Apple 요구는 최신 운영체제이므로
설정의 소프트웨어 업데이트 상태와 실제 iOS 버전을 확인한다. simulator나 fixture 화면으로 대체하지 않는다.
5–8분은 편의를 위한 권장 길이이며 Apple이 지정한 제한이 아니다. 기본 화면 기록 기능으로 충분하고
앱을 여는 장면부터 시작한다. 설치된 앱이 Debug 개발판인지 제출 빌드인지 혼동하지 않도록 확인한다.

촬영 전 준비:

- 직접 사용하고 마지막에 영구 삭제해도 되는 새 촬영용 계정과 인증 메일 수신 수단.
- 심사관용 기본 계정 및 삭제 테스트 계정은 촬영에서 삭제하지 않는다.
- 본인이 촬영한 JPEG/HEIC 사진, 신고·차단·대화를 시연할 전용 테스트 상대와 사진.
- 개인 알림이 끼어들지 않도록 준비하고 비밀번호 표시를 켜지 않는다. 인증 메일은 가능하면 다른 기기에서
  확인해 개인 메일함을 녹화하지 않는다. 동영상에 비밀번호·OTP·개인 대화가 담겼는지 제출 전 검토한다.

| 순서 | 조작 | 영상에서 확인할 결과 |
| --- | --- | --- |
| 1 | 홈 화면에서 SENSTA 실행 | 정상 실행과 공개 피드 |
| 2 | 피드 넘기기 → 사진 상세·확대 → 탐색·검색 | 비로그인 공개 열람, EXIF/사진 설명, 검색 결과 |
| 3 | 계정 → 이메일로 회원가입 → 메일 인증 → 가입 완료 | 실제 신규 계정 생성 |
| 4 | 로그아웃 → 이메일 로그인 | 로그인 완료와 내 계정 |
| 5 | 중앙 업로드 → 사진 선택·자르기/필터 → 제목·설명·태그 → 게시 | 업로드 완료, 상세와 내 작품 스튜디오 반영 |
| 6 | 테스트 상대 사진에 좋아요·댓글 | 참여 결과 표시 |
| 7 | 테스트 상대 사진의 더 보기 → 신고 → 사유 → 신고 접수 | 실제 접수 성공; 사유는 5자 이상 |
| 8 | 상대 프로필 → 차단 → 확인 → 콘텐츠 숨김 → 차단 해제 | 차단 성공과 콘텐츠/대화 제한 |
| 9 | 테스트 상대와 1:1 대화, 알림 | 전송과 알림 화면; 가능하면 상대 기기에서 실제 알림 유발 |
| 10 | 계정 → 계정 및 데이터 삭제 → DELETE → 최종 영구 삭제 | 삭제 완료와 로그아웃, 재실행 후 세션 미복원 |

계정 삭제는 복구할 수 없다. 마지막 단계는 촬영용 계정으로 제품 소유자가 직접 실행한다. Apple 로그인
연결 계정도 시연한다면 Apple 재인증·승인 폐기까지 확인하되 개인 Apple 계정 정보를 노출하지 않는다.
이메일 가입/로그인/삭제, UGC 신고/차단은 필수 범위다. 유료 기능은 없으므로 결제 시연은 해당하지 않는다.

## 영문 답변 초안

아래 대괄호는 영상 검토 후 실제 값으로 바꾼다. 완성 전에는 전송하지 않는다. 계정 비밀번호는 기존
App Review Information 입력란과 삭제 테스트 계정 안내를 참조하게 하고 공개 문서에 추가하지 않는다.

```text
Hello App Review Team,

Thank you for your Guideline 2.1 message. Here is the information for SENSTA 1.0 (2).

1. Physical-device demonstration
[VIDEO ATTACHMENT NAME OR ACCESSIBLE URL]
Device: [IPHONE MODEL], iOS [VERSION/BUILD], SENSTA 1.0 (2).
[VERIFIED CONTENTS/TIMESTAMPS]

2. Purpose and audience
SENSTA is a free photo community for photography enthusiasts, hobbyists and photographers. It helps people discover photographs, publish their own work and discuss photography through immersive viewing, editing/upload, search, profiles, comments and messages. It is a public community, not an employee-only app.

3. Setup and main features
An internet connection is required. Public feed, Explore, search, photo details and profiles work without login. Use the existing App Review Information demo credentials for account-based features. Email signup requires email verification; Apple and Google sign-in are also available. The demo account uses email/password login.
- Tap the top account icon for login (로그인) or signup (이메일로 회원가입).
- Open a photo for viewing/zoom, photo information and available AI descriptions, likes and comments/replies. Explore (탐색) searches titles, text, photographers, hashtags or photo descriptions.
- Tap the central upload button, select up to 9 photos, optionally crop/rotate/flip/apply filters, enter title/description/tags and publish. Use any reviewer-owned JPEG/HEIC photo; no special sample file is needed. Account > 내 작품 스튜디오 shows your work.
- Another photographer's profile offers 1:1 messages. Account > 1:1 메시지 opens conversations; the bell opens notifications. Allow notifications for push delivery.
- Report a photo from its detail more menu. Report/block a user from their profile or conversation more menu. Enter a reason and submit (신고 접수). Blocking hides their content and prevents interaction; the same menu can unblock.
- Account > 계정 및 데이터 삭제 deletes an account after DELETE and final confirmation. Apple-linked accounts require Apple reauthentication and token revocation. Use the separate deletion account already in Review Notes and keep the primary demo account available.
There are no purchases, subscriptions, paid content/features or advertisements.

4. Services/platforms
- Developer-operated sensta.me: NUBO/GOAPI and MySQL/MariaDB for accounts, photos, community data, messages and moderation.
- Sign in with Apple and Google Sign-In: optional authentication.
- Firebase Cloud Messaging/Installations and Apple Push Notification service: device registration and push notifications.
- Resend: verification and password-reset email delivery.
- OpenAI API on the backend: photo descriptions/search terms when photo analysis is enabled. Available descriptions are displayed without payment. Cropping/filters run on-device.

5. Regions
App Store distribution is currently South Korea only; the interface is primarily Korean. The app uses the same SENSTA community and feature set, without region-specific feature/content variants. Store availability is separate from app behavior.

6. Regulated services/content rights
SENSTA is a photography community, not a regulated financial, medical or gambling service. Photos/text are user-generated. Our terms require uploaders to hold the necessary rights and prohibit copyright infringement. Users can report/block; administrators can review reports, remove content or restrict accounts. We do not claim ownership of users' copyrights.
Terms: https://sensta.me/terms
Privacy: https://sensta.me/privacy
Support: https://sensta.me/support
```

## 제출 전 확인과 반영

1. 실제 영상에서 앱 실행·가입·로그인·삭제·신고·차단의 완료를 확인하고 기기/OS/빌드를 기록한다.
2. 실제 영상 길이와 용량, 개인정보 노출을 확인한다. Apple 첨부 또는 심사관이 접근 가능한 링크를 사용한다.
   일반 App Store 홍보용 미리보기 영역에 올리는 영상이 아니다.
3. App Review Information의 Notes에 영상 식별 정보와 2–6번 설명, 기존 삭제 계정 안내를 함께 저장한다.
   Notes의 4,000자 한도에 맞춘다.
4. 위 영문 답변을 4,000자 이내로 다듬어 App Review 회신에 넣고 영상을 첨부한다. 실제 회신 전 제품
   소유자가 Apple에 보낼 완성된 답변·영상 전송을 요청했는지 확인한다.
5. 동일 빌드로 심사 업데이트/재제출을 완료하고 화면에서 접수 상태를 확인한다. 자동 출시 설정은 유지한다.

Apple [심사 메시지 회신 안내](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages/)는
첨부 자료를 회신에 포함할 수 있고 메타데이터 문제는 수정 후 같은 빌드를 재제출할 수 있다고 설명한다.
