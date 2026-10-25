#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -n "${XCODE_DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
  elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

exec xcodebuild "$@"
