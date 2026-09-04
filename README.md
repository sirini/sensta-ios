# SENSTA iOS

[sensta.me](https://sensta.me)를 위한 iPhone 네이티브 사진 커뮤니티 앱입니다. 기존
[SENSTA Android](https://github.com/sirini/sensta)의 제품 경험과 NUBO API contract v1을 기준으로,
Swift와 SwiftUI를 사용해 Apple 플랫폼에 맞는 앱을 새로 개발합니다.

이 저장소는 현재 **개발 준비 단계**입니다. Xcode 프로젝트와 앱 기능 구현은 다음 작업 단위부터
시작합니다.

## 목표

- 로그인 없이 공개 작품을 감상하는 전체 화면 사진 피드와 탐색
- 이메일·Google·Apple 로그인과 안전한 access/refresh token 회전
- 최대 9장 사진 선택, 편집, 위치 EXIF 제거와 multipart 업로드
- 작품 상세, 다중 이미지, 댓글, 좋아요와 공유
- 사진가 프로필, 내 작품 스튜디오, 영구 업적과 축하 화면
- 1:1 대화, APNs/FCM 알림과 딥 링크
- 신고·차단·계정 및 관련 데이터 삭제
- Dynamic Type, VoiceOver, 동작 줄이기와 밝은·어두운 테마

Android 화면을 픽셀 단위로 복사하지 않습니다. 데이터와 제품 동작은 일관되게 유지하되 내비게이션,
권한 요청, 사진 선택, 공유, 로그인과 접근성은 iOS 사용자가 기대하는 방식으로 구현합니다.

## 시스템 구성

SENSTA iOS는 별도 데이터베이스를 두지 않습니다. Android와 웹이 사용하는 GOAPI에 HTTPS로 연결하고
같은 사용자, 작품, 댓글, 대화, 업적과 신고 상태를 공유합니다. Firebase는 APNs를 통한 알림 전달에만
사용할 예정입니다.

## 현재 개발 환경

- Mac: macOS 27 beta
- 기준 IDE: `/Applications/Xcode-beta.app`
- 확인된 도구: Xcode 27.0 (`27A5252f`), Swift 6.4
- 확인된 SDK와 시뮬레이터: iOS 27.0
- 실제 iPhone: 준비됨
- Apple Developer Program: 재가입 승인, Team·코드서명 연결 확인 예정

터미널에서 현재 저장소용 Xcode를 선택하고 상태를 확인합니다.

```bash
source ./scripts/xcode-env.sh
./scripts/check-environment.sh
```

시스템 전체 `xcode-select`를 바꾸지 않고 명령별 `DEVELOPER_DIR`를 사용합니다. Beta가 갱신되어도
`/Applications/Xcode-beta.app` 경로가 유지되면 같은 명령을 사용할 수 있습니다.

## 문서

- [프로젝트 상태](docs/PROJECT_STATUS.md)
- [개발 환경](docs/DEVELOPMENT_SETUP.md)
- [사전 준비 체크리스트](docs/PREPARATION_CHECKLIST.md)
- [GOAPI 사전 작업](docs/GOAPI_PREPARATION.md)
- [Firebase와 Apple 서비스 준비](docs/FIREBASE_APPLE_SETUP.md)

## 관련 프로젝트

- Android: [github.com/sirini/sensta](https://github.com/sirini/sensta)
- Backend: [github.com/sirini/goapi](https://github.com/sirini/goapi)
- Web: [github.com/sirini/nubo](https://github.com/sirini/nubo)

## 라이선스

[MIT License](LICENSE)
