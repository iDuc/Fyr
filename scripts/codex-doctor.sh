#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

status=0

pass() { printf "OK   %s\n" "$1"; }
warn() { printf "WARN %s\n" "$1"; }
fail() { printf "FAIL %s\n" "$1"; status=1; }

if [[ -f "AGENTS.md" ]]; then
  pass "AGENTS.md is present for Codex project context"
else
  fail "AGENTS.md is missing"
fi

if [[ -f "$HOME/.codex/config.toml" ]] && grep -q 'goals = true' "$HOME/.codex/config.toml"; then
  pass "Codex goals are enabled in ~/.codex/config.toml"
else
  warn "Codex goals are not enabled in ~/.codex/config.toml"
fi

if [[ -f "$HOME/.codex/config.toml" ]] && grep -q '\[projects\."/Volumes/ThunderSloerie/Development/Fyr"\]' "$HOME/.codex/config.toml"; then
  pass "Fyr is trusted in Codex config"
else
  warn "Fyr is not marked trusted in Codex config"
fi

active_developer_dir="$(env -u DEVELOPER_DIR /usr/bin/xcode-select -p 2>/dev/null || true)"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  pass "Xcode is installed at /Applications/Xcode.app"
else
  fail "Xcode.app was not found in /Applications"
fi

if [[ "$active_developer_dir" == "/Applications/Xcode.app/Contents/Developer" ]]; then
  pass "xcode-select points at Xcode"
else
  fail "xcode-select points at ${active_developer_dir:-unknown}. Fix with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

if command -v swift >/dev/null 2>&1; then
  system_swift_output="$(DEVELOPER_DIR=/Library/Developer/CommandLineTools swift --version 2>&1 | head -n 1)"
  printf "OK   %s\n" "$system_swift_output"
else
  fail "swift is not available"
fi

if command -v xcodebuild >/dev/null 2>&1; then
  first_launch_output="$(xcodebuild -checkFirstLaunchStatus 2>&1)"
  first_launch_status=$?
  xcode_output="$(xcodebuild -version 2>&1)"
  xcode_status=$?
  if [[ $first_launch_status -ne 0 ]] || printf "%s\n%s\n" "$first_launch_output" "$xcode_output" | grep -qi 'license'; then
    fail "Xcode license is not accepted. Run: sudo DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -license accept"
    printf "%s\n" "$xcode_output" | grep -vi 'license' | sed 's/^/INFO /'
  elif [[ $xcode_status -eq 0 ]]; then
    printf "%s\n" "$xcode_output" | sed 's/^/OK   /'
  else
    fail "xcodebuild is not usable: $xcode_output"
  fi
else
  fail "xcodebuild is not available"
fi

if command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices available >/dev/null 2>&1; then
  if xcrun simctl list devices available | grep -q 'iPhone 17'; then
    pass "iPhone 17 simulator runtime is available"
  else
    fail "iPhone 17 simulator was not found; install the runtime or set a supported default DESTINATION in the Makefile"
  fi
else
  fail "simctl is not available yet; this usually clears after accepting the Xcode license"
fi

if [[ -f "Fyr.xcodeproj/project.pbxproj" ]]; then
  pass "Xcode project is present"
else
  fail "Fyr.xcodeproj is missing"
fi

if [[ -f "Fyr.xcodeproj/xcshareddata/xcschemes/Fyr.xcscheme" ]]; then
  pass "Shared Fyr Xcode scheme is present"
else
  fail "Shared Fyr Xcode scheme is missing"
fi

if [[ -f "Info.plist" ]] && /usr/bin/plutil -extract NSLocalNetworkUsageDescription raw Info.plist >/dev/null 2>&1; then
  pass "Local network usage description is configured"
else
  fail "Info.plist is missing NSLocalNetworkUsageDescription"
fi

if [[ -f "Fyr/Fyr.entitlements" ]] && grep -q 'group.com.fyr.app' Fyr/Fyr.entitlements; then
  pass "Main app App Group entitlement is configured"
else
  fail "Main app App Group entitlement is missing"
fi

if [[ -f "Fyr/Fyr.entitlements" ]] && grep -q 'com.apple.developer.siri' Fyr/Fyr.entitlements; then
  pass "Main app Siri entitlement is configured"
else
  fail "Main app Siri entitlement is missing"
fi

if [[ -f "FyrWidgetExtension.entitlements" ]] && grep -q 'group.com.fyr.app' FyrWidgetExtension.entitlements; then
  pass "Widget App Group entitlement is configured"
else
  fail "Widget App Group entitlement is missing"
fi

if grep -q 'com.apple.ApplicationGroups.iOS' Fyr.xcodeproj/project.pbxproj && grep -q 'com.apple.Siri' Fyr.xcodeproj/project.pbxproj; then
  pass "Xcode project capabilities include App Groups and Siri"
else
  fail "Xcode project capabilities are missing App Groups or Siri"
fi

if command -v brew >/dev/null 2>&1 && brew list --versions libmodbus >/dev/null 2>&1; then
  pass "libmodbus is installed for bridge diagnostics"
else
  fail "libmodbus is not installed. Install with: brew install libmodbus"
fi

if command -v xcbeautify >/dev/null 2>&1; then
  pass "xcbeautify is installed for readable xcodebuild logs"
else
  fail "xcbeautify is not installed. Install with: brew install xcbeautify"
fi

if command -v brew >/dev/null 2>&1; then
  brew_prefix="$(brew --prefix 2>/dev/null)"
  if [[ -n "$brew_prefix" && -w "$brew_prefix" ]]; then
    pass "Homebrew prefix is writable"
  elif [[ -n "$brew_prefix" ]]; then
    warn "Homebrew prefix is not writable. Future brew installs may need: sudo chown -R $(id -un) $brew_prefix"
  else
    fail "Homebrew is installed but brew --prefix failed"
  fi
else
  fail "Homebrew is not installed"
fi

printf "\n"
if [[ "$status" -eq 0 ]]; then
  pass "Fyr Codex environment is ready"
else
  fail "Fyr Codex environment still needs setup. For machine-level fixes, run: make bootstrap"
fi

exit "$status"
