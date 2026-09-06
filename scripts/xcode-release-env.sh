#!/usr/bin/env bash

# TestFlight와 App Store 제출에는 beta가 아닌 정식 Xcode를 저장소 범위에서만 사용한다.
sensta_ios_release_xcode_app="${SENSTA_IOS_RELEASE_XCODE_APP:-/Applications/Xcode.app}"

if [[ ! -d "$sensta_ios_release_xcode_app/Contents/Developer" ]]; then
  echo "SENSTA iOS: 정식 Xcode를 찾을 수 없습니다: $sensta_ios_release_xcode_app" >&2
  return 1 2>/dev/null || exit 1
fi

export SENSTA_IOS_RELEASE_XCODE_APP="$sensta_ios_release_xcode_app"
export DEVELOPER_DIR="$sensta_ios_release_xcode_app/Contents/Developer"

echo "SENSTA iOS Release: DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -version
