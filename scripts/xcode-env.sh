#!/usr/bin/env bash

# 개발과 제출에 같은 RC를 선택하고 시스템 전역 설정은 변경하지 않는다.
sensta_ios_xcode_app="${SENSTA_IOS_XCODE_APP:-/Applications/Xcode-27-RC.app}"

if [[ ! -d "$sensta_ios_xcode_app/Contents/Developer" ]]; then
  echo "SENSTA iOS: Xcode를 찾을 수 없습니다: $sensta_ios_xcode_app" >&2
  return 1 2>/dev/null || exit 1
fi

export SENSTA_IOS_XCODE_APP="$sensta_ios_xcode_app"
export DEVELOPER_DIR="$sensta_ios_xcode_app/Contents/Developer"

echo "SENSTA iOS: DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -version
