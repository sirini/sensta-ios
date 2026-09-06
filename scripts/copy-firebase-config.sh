#!/usr/bin/env bash

set -euo pipefail

firebase_source="${FIREBASE_CONFIG_FILE:-}"
firebase_destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"

if [[ -z "$firebase_source" || ! -f "$firebase_source" ]]; then
  echo "warning: Firebase configuration is missing: ${firebase_source:-FIREBASE_CONFIG_FILE}" >&2
  exit 0
fi

install -m 0644 "$firebase_source" "$firebase_destination"
