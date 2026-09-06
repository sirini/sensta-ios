# 사전 준비 체크리스트

## Apple 계정과 개발 기기

- [x] Apple Developer Program 재가입 신청
- [x] 결제 카드 등록
- [x] Apple Developer Program 재가입 승인
- [x] 연간 멤버십 결제와 활성 상태 확인
- [x] Team ID `WKPCU58CWL`와 2027-09-04 만료일 확인
- [x] Apple Developer 계약과 App Store Connect 이용 약관 동의
- [x] Xcode에 Apple Account와 Team `WKPCU58CWL` 연결
- [x] 개발용 iPhone 준비
- [x] Xcode 27 beta와 iOS 27 simulator 설치
- [x] Xcode 라이선스 동의와 초기 구성 완료
- [x] iPhone을 Xcode에 연결하고 개발자 모드·자동 서명·설치·실행 확인

개인정보나 인증서 비밀키는 문서와 Git에 기록하지 않는다.

## 앱 식별자와 범위

- [x] 재활성화된 계정의 기존 SENSTA App ID·App Store Connect 레코드 확인
- [x] 2011년 레거시 개발 기기 3대 제거와 연간 등록 슬롯 초기화
- [x] 운영 bundle ID 확정: `me.sensta.ios`
- [x] 개발 bundle ID 확정: `me.sensta.ios.debug`
- [x] App Store Connect에서 `SENSTA` 앱 생성: Apple ID `6808687447`
- [x] 무료 가격, 대한민국 배포, 사진 및 비디오·소셜 네트워킹 카테고리와 수동 출시 설정
- [x] Apple Silicon Mac과 Apple Vision Pro 자동 배포 해제
- [x] 최소 지원 iOS 버전 확정: iOS 17 이상
- [x] 초기 iPhone 전용 방향 확정, iPad는 별도 QA 뒤 확대
- [x] 알림 deep link 범위 확정: 사진 활동은 상세, 1:1 메시지는 해당 대화
- [ ] 웹 Universal Link 범위 확정

## GOAPI와 NUBO

- [x] 공용 Google server client audience와 mobile 인증·refresh 계약
- [x] Sign in with Apple 서버 검증과 외부 계정 연결 정책
- [x] `ios` push platform 등록과 APNs/FCM alert payload 구현 및 운영 반영 (`GOAPI b6b9b0f`, `1ccf15a`)
- [x] `sensta-ios` 게시글 출처와 플랫폼 공통 `sensta-app` 업적 정책
- [x] HEIC/JPEG 방향 정규화, 썸네일, EXIF와 GPS 제거 계약
- [x] Apple 계정 삭제용 GOAPI `24bcc4d`와 Team ID·Key ID·Sign in with Apple `.p8` 운영 설정
- [ ] UGC 게시 전 필터와 신고 처리 운영 계약
- [ ] iOS가 사용하는 endpoint별 request/response fixture
- [ ] GOAPI 보안 회귀 테스트와 NUBO API contract 문서 갱신

세부 내용은 [GOAPI 사전 작업](GOAPI_PREPARATION.md)을 따른다.

## Firebase와 Apple 서비스

- [x] Firebase 프로젝트에 운영 iOS 앱 등록
- [x] Firebase 프로젝트에 개발 iOS 앱 등록
- [x] 각 앱의 `GoogleService-Info.plist`를 구성별 로컬 경로에 안전하게 배치
- [x] 운영·개발 Apple App ID에서 Push Notifications 활성화
- [x] 운영·개발 Apple App ID에서 Associated Domains와 Sign in with Apple 활성화
- [x] Sandbox·Production APNs 인증 키 생성 및 각 Firebase iOS 앱 환경에 업로드
- [x] Google OAuth iOS client ID 생성
- [x] Sign in with Apple server configuration과 GOAPI 검증 준비
- [x] 실제 iPhone에서 foreground/background/종료 상태 알림과 사진·1:1 대화 deep link 검증

세부 내용은 [Firebase와 Apple 서비스 준비](FIREBASE_APPLE_SETUP.md)를 따른다.

## 개인정보·UGC·App Store 심사

- [x] 공개 개인정보처리방침: `https://sensta.me/privacy`
- [x] 공개 이용약관: `https://sensta.me/terms`
- [x] 공개 계정 삭제 안내: `https://sensta.me/delete-account`
- [ ] 전용 지원 URL 준비: 현재 `https://sensta.me/support`는 없음
- [ ] 신고·차단·운영자 조치·부적절 콘텐츠 필터의 심사 시나리오 작성
- [ ] App Privacy 데이터 수집표 작성
- [x] Firebase·Google 등 third-party SDK privacy manifest가 Release 앱 번들에 포함되는지 확인
- [ ] 앱 내 계정 삭제와 Sign in with Apple token 폐기 검증
- [ ] 연령 등급 질문, 콘텐츠 권리와 수출 규정 답변 준비
- [x] 대한민국 비즈니스 규정 준수용 연락처 및 사업자등록번호 보유 여부 확인 완료
- [ ] App Review용 테스트 계정과 검토 메모 준비
- [ ] 1024px App Store 아이콘과 기기별 스크린샷 준비
- [ ] TestFlight 내부 테스트 후 실제 사용자 여정 회귀 테스트

## 첫 개발 세션

- [x] Xcode 프로젝트와 unit/UI test target 생성
- [x] 저장소 shared scheme과 Debug/Release build configuration 정리
- [x] API base URL을 xcconfig로 분리: `https://sensta.me/goapi/`
- [x] 공통 API envelope와 오류 code 모델 구현
- [x] 공개 게시글 목록 fixture decoding test 작성
- [x] 빈 상태·통신 실패·재시도 UI를 포함한 첫 피드 화면 구현
