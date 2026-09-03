#!/usr/bin/env bash
set -euo pipefail

sensta_ios_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=xcode-env.sh
source "$sensta_ios_script_dir/xcode-env.sh" >/dev/null

sensta_ios_macos_version="$(sw_vers -productVersion)"
sensta_ios_xcode_version="$(xcodebuild -version | sed -n '1p')"
sensta_ios_swift_version="$(xcrun swift --version 2>&1 | sed -n '1p')"
sensta_ios_runtimes="$(xcrun simctl list runtimes)"

echo "macOS: $sensta_ios_macos_version"
echo "Xcode app: $SENSTA_IOS_XCODE_APP"
echo "Xcode: $sensta_ios_xcode_version"
echo "Swift: $sensta_ios_swift_version"

if [[ "$sensta_ios_xcode_version" != "Xcode 27."* ]]; then
  echo "오류: 현재 준비 단계는 Xcode 27 계열을 기대합니다." >&2
  exit 1
fi

if ! grep -q "iOS 27.0" <<<"$sensta_ios_runtimes"; then
  echo "오류: iOS 27.0 simulator runtime을 찾지 못했습니다." >&2
  exit 1
fi

echo "Simulator: iOS 27.0 runtime 확인"
echo "준비 상태: 정상"
