#!/usr/bin/env bash
set -euo pipefail

sensta_ios_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sensta_ios_root_dir="$(cd "$sensta_ios_script_dir/.." && pwd)"
# shellcheck source=xcode-release-env.sh
source "$sensta_ios_script_dir/xcode-release-env.sh" >/dev/null

sensta_ios_xcode_line="$(xcodebuild -version | sed -n '1p')"
sensta_ios_xcode_major="${sensta_ios_xcode_line#Xcode }"
sensta_ios_xcode_major="${sensta_ios_xcode_major%%.*}"
sensta_ios_xcode_build="$(xcodebuild -version | sed -n 's/^Build version //p')"

echo "Xcode app: $SENSTA_IOS_RELEASE_XCODE_APP"
echo "Xcode: $sensta_ios_xcode_line"
echo "Xcode build: $sensta_ios_xcode_build"
echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"

# 버전 숫자만 검사하면 beta나 이전에 실패한 Xcode로 다시 제출할 수 있다.
# 제출 도구를 바꿀 때는 Apple 릴리스 노트를 재확인하고 이 기준도 함께 갱신한다.
if [[ "$sensta_ios_xcode_build" != "27A266a" ]]; then
  echo "오류: 현재 검증된 제출 기준은 Xcode 27 RC (27A266a)입니다." >&2
  exit 1
fi

sensta_ios_sdks="$(xcodebuild -showsdks)"
sensta_ios_runtimes="$(xcrun simctl list runtimes)"

if [[ ! "$sensta_ios_xcode_major" =~ ^[0-9]+$ ]] || (( sensta_ios_xcode_major < 26 )); then
  echo "오류: 2026-04-28 이후 제출에는 Xcode 26 이상이 필요합니다." >&2
  exit 1
fi

if ! grep -Eq 'iphoneos2[6-9]\.' <<<"$sensta_ios_sdks"; then
  echo "오류: iOS 26 이상 SDK를 찾지 못했습니다." >&2
  exit 1
fi

if ! grep -Eq 'iOS 2[6-9]\..*com\.apple\.CoreSimulator\.SimRuntime' <<<"$sensta_ios_runtimes"; then
  echo "오류: iOS 26 이상 simulator runtime을 찾지 못했습니다." >&2
  exit 1
fi

sensta_ios_required_files=(
  "$sensta_ios_root_dir/Config/Release.local.xcconfig"
  "$sensta_ios_root_dir/Config/Firebase/Release/GoogleService-Info.plist"
  "$sensta_ios_root_dir/SENSTA/PrivacyInfo.xcprivacy"
)

for sensta_ios_required_file in "${sensta_ios_required_files[@]}"; do
  if [[ ! -f "$sensta_ios_required_file" ]]; then
    echo "오류: 제출 빌드에 필요한 로컬 파일이 없습니다: $sensta_ios_required_file" >&2
    exit 1
  fi
done

plutil -lint "$sensta_ios_root_dir/SENSTA/PrivacyInfo.xcprivacy" >/dev/null

echo "SDK: iOS 26 이상 확인"
echo "Simulator: iOS 26 이상 runtime 확인"
echo "Release 로컬 설정·Firebase 설정·Privacy Manifest 확인"
echo "제출 환경: 정상"
