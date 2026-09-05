# 계정 로그인과 세션

## 구현 범위

기존 SENSTA 이메일·비밀번호 계정으로 로그인하고, 내 공개 프로필로 이동하며, 로그아웃한다.
피드 우상단 사람 아이콘에서 iOS 기본 Form 시트를 연다. 공개 사진 감상은 로그인 없이 유지한다.
Google·Apple 로그인, 회원가입·비밀번호 재설정, 좋아요·댓글 작성은 후속 기능이다.

## 기존 Android/GOAPI 계약

| 동작 | 요청 | 처리 |
| --- | --- | --- |
| 로그인 | `POST /auth/signin`, form `id`, `password` | `uid`, `name`, `id`, `blocked`, `token`, `refresh` |
| 세션 확인 | `GET /auth/load`, Bearer access token | 존재하는 비차단 계정만 로그인 상태로 표시 |
| 토큰 갱신 | `POST /auth/android/refresh`, JSON `refresh` | access/refresh 쌍을 교체한 뒤 세션 확인 재시도 |
| 로그아웃 | `POST /auth/logout`, Bearer access token | 로컬 삭제 성공 후 서버에도 폐기를 요청 |

GOAPI와 Android·NUBO 요청 계약은 변경하지 않는다. 로그인 비밀번호는 해시하거나 공백을 제거하지
않으며 HTTPS form으로 전달한다. 이메일 양끝 공백만 제거한다. `/auth/android/refresh`는 플랫폼 검사가
없는 기존 네이티브 계약이다. 서버가 사용자별 refresh token을 관리하는 기존 정책도 그대로 따른다.

## 저장과 오류 복구

- access/refresh 쌍만 API base URL과 bundle ID로 구분한 Keychain 단일 항목에 저장한다.
  `WhenUnlockedThisDeviceOnly`를 사용해 기기 간 동기화·백업 이동을 하지 않는다.
- 사용자 정보는 메모리에만 유지하고 비밀번호는 요청 직후 입력란에서 지운다.
- 인증 URLSession은 ephemeral이며 쿠키·디스크 캐시·HTTP 리다이렉트를 사용하지 않는다.
- 앱 시작 시 저장된 access token으로 계정을 확인하고, HTTP 401일 때만 refresh를 한 번 시도한다.
  회전된 토큰은 후속 계정 조회 전에 저장한다. 중복 세션 작업은 실행하지 않는다.
- 통신 실패는 저장된 세션을 보존하고 재시도를 제공한다. 서버가 만료·무효 토큰을 거부하면 삭제하고
  다시 로그인을 요청한다. 차단 계정은 로그인 완료로 표시하지 않는다.
- Keychain 저장·삭제 실패를 성공으로 표시하지 않는다. 로그아웃 시 로컬 삭제가 먼저 완료되며,
  오프라인이면 서버 폐기는 완료되지 않을 수 있다. 서버의 access token 만료 정책은 유지한다.
- 공개 피드·상세·검색·댓글 조회에는 인증 토큰을 추가하지 않는다. 인증 기반 참여 기능을 구현할 때
  해당 조회의 개인별 상태와 토큰 갱신을 함께 연결한다.

## 실기기 QA

피드 우상단 사람 아이콘 → 기존 이메일 로그인 → 내 공개 프로필 → 앱 종료·재실행 → 계정 복원 →
로그아웃을 확인한다. 로그인 실패·통신 단절 시 기존 사진 감상이 유지되는지도 확인한다.
실제 계정 비밀번호는 제품 소유자가 iPhone에서 직접 입력한다.
