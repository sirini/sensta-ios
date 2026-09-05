# GOAPI 사전 작업

SENSTA iOS는 기존 GOAPI API contract v1을 최대한 재사용한다. Android 호환성을 깨지 않는 additive
변경을 원칙으로 하며, 인증과 권한 변경에는 회귀 테스트를 먼저 추가한다.

## 1. 모바일 인증 계약 일반화

현재 Android는 다음 직접 경로를 사용한다.

- `POST /auth/android/google`
- `POST /auth/android/refresh`

필요 작업:

- 2026-09-05 소스 확인: Google handler와 `MobileRefreshAccessTokenHandler`는 Android 기기 검사를
  하지 않는다. 기존 token audience·form/body 계약이 맞으면 iOS도 같은 경로를 사용할 수 있다. 실제 iOS
  OAuth 발급 검증은 로그인 작업에서 수행한다.
- `/auth/mobile/google`과 `/auth/mobile/refresh` 별칭은 선택 사항이며, 이름만 바꾸기 위한 서버 배포는
  선행 조건으로 두지 않는다. 기존 Android 경로·설정과 응답 계약을 유지한다.
- iOS 앱 자체에는 iOS 유형 OAuth client ID가 필요하지만, GOAPI로 보낼 ID token은 Android와 같은 Web
  유형 server client ID를 audience로 발급받는다. iOS client ID를 서버 audience로 혼동하지 않는다.
- 기존 `OAUTH_GOOGLE_ANDROID_CLIENT_ID`가 실제로 가리키는 Web server client ID를 하위 호환을 유지하며
  공용 mobile 설정으로 일반화한다.
- 현재 production handler의 Google `tokeninfo` HTTP 호출은 디버깅 용도에 가깝다. Google 공개 키를
  캐시하는 검증 라이브러리로 signature, issuer, audience와 expiry를 검증하고 인증된 이메일만 사용한다.
- 장기적으로는 변경 가능한 이메일 대신 `provider + sub`를 외부 identity의 불변 키로 사용한다. 기존
  SENSTA 계정 연결 규칙은 Apple 로그인용 external identity schema와 함께 명시적으로 설계한다.
- access token 만료 시 refresh token을 회전하고 새 token 쌍을 원자적으로 저장하는 기존 계약을 유지한다.
- 정지·탈퇴·존재하지 않는 사용자는 소셜 로그인과 refresh에서도 거부한다.
- iOS 클라이언트는 access/refresh token을 Keychain에 저장하며 로그에 남기지 않는다.

## 2. Sign in with Apple

Google 로그인을 제공하는 iOS 앱의 심사와 사용자 편의를 위해 Sign in with Apple을 구현한다.

- Apple identity token과 nonce를 서버에서 검증한다.
- 이메일이 아니라 `provider + subject`를 외부 identity의 불변 키로 사용한다.
- Apple 비공개 이메일, 최초 로그인에만 전달되는 이름과 기존 SENSTA 계정 연결 흐름을 정의한다.
- 이메일 일치만으로 계정을 자동 병합하지 않는다. 로그인된 기존 계정에서 명시적으로 연결하거나 별도
  확인 절차를 사용한다.
- Apple 자격 증명 취소와 서버 간 알림 처리 정책을 정한다.
- 계정 삭제 시 SENSTA 데이터 삭제와 함께 Apple token을 폐기한다.

기존 `user.id` 중심 구조에 직접 provider 값을 끼워 넣기보다 별도 external identity 매핑을 추가하는 편이
안전하다. schema와 마이그레이션은 여러 NUBO 배포에서 재사용 가능해야 한다.

## 3. iOS push 등록과 전송

현재 `push_device.platform`은 문자열이지만 서비스 검증은 `android`만 허용한다.

- `ios`를 허용하고 platform별 등록·해제 테스트를 추가한다.
- Firebase Installation ID 또는 최종 채택한 registration token 의미를 Android와 iOS 문서에서 정확히
  통일한다.
- Firebase Admin multicast가 Android와 APNs 설정을 함께 전달하도록 구성한다.
- notification title/body, data payload, sound, category, background update와 deep link 필드를 확정한다.
- 만료·폐기된 iOS device token도 Android와 동일하게 정리한다.
- 다른 사용자로 로그인할 때 한 기기 token이 이전 계정에 남지 않는지 검증한다.

## 4. 앱 출처와 업적

사진 첨부 게시글의 `sensta-app` 업적은 Android와 iOS를 구분하지 않는 하나의 영구 업적이다.

- Android는 `X-Nubo-Client: sensta-android`, iOS는 `X-Nubo-Client: sensta-ios`를 보낸다.
- 서버는 두 출처를 각 게시글의 `post_origin`에 구분해 기록하지만 동일한 `sensta-app` 업적을 수여한다.
- 관리 화면의 정의는 `SENSTA 앱 포토그래퍼`이며 사용자별 `(user_uid, badge_key)`가 유일하므로 어느
  플랫폼에서 먼저 획득해도 중복 수여되지 않는다.
- 헤더는 인증 수단이 아니며 사용자 UID는 JWT에서만 가져온다.

## 5. iPhone 사진 업로드

iOS 앱은 선택한 JPEG·HEIC 사진을 방향이 정규화된 JPEG로 변환하고 긴 변을 4096px로 제한한 뒤 정확한
GPS 메타데이터를 제거해 기존 multipart 계약으로 보낸다. GOAPI는 저장된 JPEG를 기존 썸네일·EXIF·AI
설명 경로로 처리한다. 원본 HEIC를 서버에 직접 보내는 계약은 사용하지 않는다.
- 정확한 GPS 관련 EXIF는 공개 업로드 전에 제거한다.
- 최대 9장·합계 100MB, 취소, 부분 실패와 임시 파일 정리를 회귀 테스트한다.
- Live Photo와 RAW는 첫 릴리스 범위에서 제외하고 사용자에게 처리 결과를 명확히 알린다.

## 6. UGC 심사 준비

기존 신고·차단·관리자 신고 처리에 더해 App Store UGC 심사에서 설명 가능한 운영 계약을 준비한다.

- 서버 측 텍스트 금칙어·스팸 필터 또는 동등한 부적절 콘텐츠 차단 수단
- 사진 신고, 사용자 신고, 차단과 차단 해제 흐름
- 운영자가 신고를 확인하고 조치하는 목표 시간과 사용자 안내
- 공개 연락처와 지원 URL
- 심사 테스트 계정에서 위 기능을 재현하는 절차

## 7. 계약과 검증

- iOS가 소비하는 endpoint만 먼저 표로 고정하고 실제 GOAPI binding 형식을 기록한다.
- 공통 success/error envelope, HTTP 401 예외, code 분기를 Swift fixture test로 고정한다.
- Android DTO fixture와 동일한 JSON을 가능한 범위에서 공동 사용한다.
- 공용 mobile Google 경로와 기존 Android 경로가 동일한 Web server client audience와 응답 계약을
  유지하는지 회귀 테스트한다.
- GOAPI 변경 후 관련 focused test, `go test ./...`, `go vet ./...`를 실행한다.
- 인증·업로드·알림 계약이 바뀌면 NUBO API contract와 Sensta Android 영향을 함께 확인한다.
