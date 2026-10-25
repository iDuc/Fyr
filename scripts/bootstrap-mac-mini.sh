#!/usr/bin/env bash
set -euo pipefail

XCODE_DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"

if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
  echo "Xcode was not found at $XCODE_DEVELOPER_DIR"
  echo "Install Xcode from the App Store or set XCODE_DEVELOPER_DIR to the installed Xcode developer directory."
  exit 1
fi

echo "Requesting sudo access for one-time Mac mini setup..."
sudo -v

echo "Configuring xcode-select..."
sudo xcode-select -s "$XCODE_DEVELOPER_DIR"

echo "Accepting Xcode license and completing first-launch setup..."
sudo DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -license accept
sudo DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -runFirstLaunch

if [[ -n "$BREW_PREFIX" ]]; then
  if [[ ! -w "$BREW_PREFIX" ]]; then
    echo "Repairing Homebrew ownership for $BREW_PREFIX..."
    sudo chown -R "$(id -un)" "$BREW_PREFIX"
  fi

  brew_tools=()
  if ! brew list --versions libmodbus >/dev/null 2>&1; then
    brew_tools+=(libmodbus)
  fi
  if ! command -v xcbeautify >/dev/null 2>&1; then
    brew_tools+=(xcbeautify)
  fi

  if [[ "${#brew_tools[@]}" -gt 0 ]]; then
    echo "Installing optional Fyr diagnostics/build-log tools..."
    brew install "${brew_tools[@]}"
  else
    echo "Optional Fyr diagnostics/build-log tools are already installed."
  fi
else
  echo "Homebrew was not found. Skipping libmodbus and xcbeautify installation."
fi

echo "Running final environment check..."
make doctor
