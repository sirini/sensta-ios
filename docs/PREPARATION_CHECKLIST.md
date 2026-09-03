# 사전 준비 체크리스트

## Apple 계정과 개발 기기

- [x] Apple Developer Program 재가입 신청
- [x] 결제 카드 등록
- [ ] Apple 심사 승인 메일 수신
- [ ] 실제 카드 결제 완료 확인
- [ ] Developer 계정의 활성 상태, Team ID와 만료일 확인
- [ ] Xcode에 Apple Account와 활성 Team 연결
- [x] 개발용 iPhone 준비
- [x] Xcode 27 beta와 iOS 27 simulator 설치
- [ ] iPhone을 Xcode에 연결하고 개발자 모드·서명·실행 확인

개인정보나 인증서 비밀키는 문서와 Git에 기록하지 않는다.

## 앱 식별자와 범위

- [ ] 운영 bundle ID 확정: 제안 `me.sensta.ios`
- [ ] 개발 bundle ID 확정: 제안 `me.sensta.ios.debug`
- [ ] App Store Connect에서 `SENSTA` 이름과 앱 레코드 생성
- [ ] 최소 지원 iOS 버전 확정
- [ ] 초기 iPhone 지원 방향과 iPad 노출 정책 확정
- [ ] Universal Link와 알림 deep link 범위 확정

## GOAPI와 NUBO

- [ ] iOS용 Google token audience와 mobile refresh 계약
- [ ] Sign in with Apple 서버 검증과 외부 계정 연결 정책
- [ ] `ios` push platform 등록과 APNs/FCM payload
- [ ] `sensta-ios` 게시글 출처와 `sensta-app` 업적 정책
- [ ] HEIC/JPEG 업로드, 썸네일, EXIF와 GPS 제거 계약
- [ ] UGC 게시 전 필터와 신고 처리 운영 계약
- [ ] iOS가 사용하는 endpoint별 request/response fixture
- [ ] GOAPI 보안 회귀 테스트와 NUBO API contract 문서 갱신

세부 내용은 [GOAPI 사전 작업](GOAPI_PREPARATION.md)을 따른다.

## Firebase와 Apple 서비스

- [ ] Firebase 프로젝트에 운영 iOS 앱 등록
- [ ] Firebase 프로젝트에 개발 iOS 앱 등록
- [ ] 각 앱의 `GoogleService-Info.plist`를 로컬에 안전하게 배치
- [ ] Apple App ID에서 Push Notifications 활성화
- [ ] APNs 인증 키 생성 및 Firebase Console에 업로드
- [ ] Google OAuth iOS client ID 생성
- [ ] Sign in with Apple capability와 server configuration 준비
- [ ] 실제 iPhone에서 foreground/background/종료 상태 알림 검증

세부 내용은 [Firebase와 Apple 서비스 준비](FIREBASE_APPLE_SETUP.md)를 따른다.

## 개인정보·UGC·App Store 심사

- [x] 공개 개인정보처리방침: `https://sensta.me/privacy`
- [x] 공개 이용약관: `https://sensta.me/terms`
- [x] 공개 계정 삭제 안내: `https://sensta.me/delete-account`
- [ ] 전용 지원 URL 준비: 현재 `https://sensta.me/support`는 없음
- [ ] 신고·차단·운영자 조치·부적절 콘텐츠 필터의 심사 시나리오 작성
- [ ] App Privacy 데이터 수집표 작성
- [ ] Firebase·Google 등 third-party SDK privacy manifest 확인
- [ ] 앱 내 계정 삭제와 Sign in with Apple token 폐기 검증
- [ ] 연령 등급 질문, 콘텐츠 권리와 수출 규정 답변 준비
- [ ] App Review용 테스트 계정과 검토 메모 준비
- [ ] 1024px App Store 아이콘과 기기별 스크린샷 준비
- [ ] TestFlight 내부 테스트 후 실제 사용자 여정 회귀 테스트

## 첫 개발 세션

- [ ] Xcode 프로젝트와 unit/UI test target 생성
- [ ] 저장소 shared scheme과 build configuration 정리
- [ ] API base URL을 xcconfig로 분리
- [ ] 공통 API envelope와 오류 code 모델 구현
- [ ] 공개 게시글 목록 fixture decoding test 작성
- [ ] 빈 상태·통신 실패·재시도 UI를 포함한 첫 피드 화면 구현
