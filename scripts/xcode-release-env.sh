#!/usr/bin/env bash

# 2026-09-09부터 Apple이 App Store 제출을 허용한 Xcode 27 RC를 저장소 범위에서 사용한다.
sensta_ios_release_xcode_app="${SENSTA_IOS_RELEASE_XCODE_APP:-/Applications/Xcode-27-RC.app}"

if [[ ! -d "$sensta_ios_release_xcode_app/Contents/Developer" ]]; then
  echo "SENSTA iOS: 제출용 Xcode를 찾을 수 없습니다: $sensta_ios_release_xcode_app" >&2
  return 1 2>/dev/null || exit 1
fi

export SENSTA_IOS_RELEASE_XCODE_APP="$sensta_ios_release_xcode_app"
export DEVELOPER_DIR="$sensta_ios_release_xcode_app/Contents/Developer"

echo "SENSTA iOS Release: DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -version
