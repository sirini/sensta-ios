# 개발 환경

## 확인된 환경

2026-09-05 기준으로 다음 구성을 확인했다.

| 항목 | 상태 |
| --- | --- |
| 운영체제 | macOS 27 beta |
| 기본 Xcode | Xcode 26.6, 현재 macOS와 호환되지 않음 |
| 개발 Xcode | `/Applications/Xcode-beta.app`, Xcode 27.0 (`27A5252f`) |
| Swift | 6.4 |
| iOS SDK | iOS 27.0 |
| Simulator runtime | iOS 27.0 (`24A5423a`) |
| 실제 기기 | iPhone 준비됨 |
| Xcode 초기 설정 | 라이선스 동의와 추가 구성 완료 |
| Apple Developer Program | 활성, Team `WKPCU58CWL`, 2027-09-04 만료 |
| App Store Connect | `SENSTA` Apple ID `6808687447`, 대한민국 무료 배포 준비 중 |
| Xcode 프로젝트 | SwiftUI app과 unit/UI test target, Debug/Release 빌드 확인 |

`xcode-select`는 Xcode 26.6을 가리킬 수 있으므로 단순히 `xcodebuild`나 `/usr/bin/git`을 실행하면
호환성 또는 라이선스 오류가 발생할 수 있다. 저장소 작업에서는 Xcode 27 beta의 Developer 디렉터리를
명시한다.

## 셸 설정

저장소 루트에서 다음 명령을 실행한다.

```bash
source ./scripts/xcode-env.sh
./scripts/check-environment.sh
```

스크립트의 기본 Xcode 경로는 `/Applications/Xcode-beta.app`이다. 다른 이름이나 위치를 사용하면 먼저
다음 변수를 지정한다.

```bash
export SENSTA_IOS_XCODE_APP=/Applications/Xcode-beta.app
source ./scripts/xcode-env.sh
```

이 설정은 현재 셸에만 적용되며 시스템 전체 `xcode-select`를 바꾸지 않는다. Git 명령도 Apple command
line tool 선택의 영향을 받을 수 있으므로 현재 beta 기간에는 위 스크립트를 먼저 source한다.

## Beta 업데이트

Beta 8 또는 이후 빌드로 교체할 때는 앱 이름을 `Xcode-beta.app`으로 유지하고 다음을 다시 확인한다.

1. Xcode를 직접 한 번 실행해 추가 구성요소 설치와 라이선스를 처리한다.
2. `scripts/check-environment.sh`가 Xcode 27, iOS 27 SDK와 runtime을 찾는지 확인한다.
3. 기존 시뮬레이터가 부팅되는지 확인한다.
4. 프로젝트가 생긴 뒤에는 전체 unit/UI test와 Debug build를 다시 실행한다.

Beta 도구 자체의 결함과 앱 결함을 구분하기 위해 release 준비 시점에는 Apple이 App Store Connect에서
허용하는 안정판 Xcode로 동일 테스트와 archive를 다시 수행한다.

## 확정한 프로젝트 값

- Product Name: `SENSTA`
- Interface: SwiftUI
- Language: Swift
- 테스트: unit test와 UI test target 포함
- Team: `WKPCU58CWL`
- 운영 bundle ID: `me.sensta.ios`
- 개발 bundle ID: `me.sensta.ios.debug`
- 최소 지원 버전: iOS 17 이상
- iPad: 초기에는 iPhone 전용으로 시작하고 별도 QA 후 확대
- Debug API: `https://sensta.me/goapi/`
- Release API: `https://sensta.me/goapi/`

Xcode가 자동으로 만든 사용자별 signing과 scheme 상태는 커밋하지 않는다. 프로젝트 파일, shared scheme,
asset catalog와 테스트 target은 커밋한다.

## 빌드와 테스트

저장소 루트에서 Xcode 27 beta 환경을 선택한 뒤 실행한다.

```bash
source ./scripts/xcode-env.sh
xcodebuild -project SENSTA.xcodeproj -scheme SENSTA \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project SENSTA.xcodeproj -scheme SENSTA \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## 실제 iPhone 자동 서명

현재 프로젝트에는 Team `WKPCU58CWL`과 Automatic Signing이 설정되어 있다. 이 Mac의 Xcode에는 아직
Apple Account가 추가되지 않았고 연결된 iPhone도 없어 실기기용 인증서와 provisioning profile은 생성되지
않았다.

1. Xcode에서 **Xcode → Settings → Accounts**를 열고 개발자 Apple Account를 추가한다.
2. iPhone을 Mac에 연결해 신뢰와 개발자 모드를 승인한다.
3. `SENSTA.xcodeproj`를 열고 `SENSTA` scheme, 연결한 iPhone을 선택해 Run한다.
4. Xcode가 생성한 Apple Development 인증서와 provisioning profile은 내보내거나 Git에 추가하지 않는다.
