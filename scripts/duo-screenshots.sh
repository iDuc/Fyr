#!/usr/bin/env bash
# Screenshots of Fyr on the iPhone Duo simulator: open / half folded / closed,
# light / dark, burning (wave) / off. Uses the DEBUG app from DerivedData and
# the fake bridge on 127.0.0.1 (scripts/fake-dru-bridge.py) - never a real bridge.
#
# Run inside a reservation (sets SIMULATOR_UDID):
#   sloerie-simulators run --device duo --agent <agent> --task "Fyr Duo screenshots" -- scripts/duo-screenshots.sh
set -euo pipefail

UDID="${SIMULATOR_UDID:?run inside sloerie-simulators run}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-/Volumes/ThunderSloerie/BuildArtifacts/Fyr/phase3/screens}"
APP="${APP:-/Volumes/ThunderSloerie/BuildArtifacts/Fyr/DerivedData/Build/Products/Debug-iphonesimulator/Fyr.app}"
PORT="${PORT:-15020}"
LANGUAGE="${LANGUAGE:-nl}"
BUNDLE=com.vanYperen.Fyr
HINGE="${HINGE:-$HOME/.local/bin/hinge}"
mkdir -p "$OUT"

state="$(xcrun simctl list devices | grep "$UDID" || true)"
if [[ "$state" != *"(Booted)"* ]]; then
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "19:42" --batteryState charged --batteryLevel 100 --wifiBars 3 || true

BRIDGE_PID=""
start_bridge() {
  stop_bridge
  python3 -I "$ROOT/scripts/fake-dru-bridge.py" --port "$PORT" "$@" > "$OUT/fake-bridge.log" 2>&1 &
  BRIDGE_PID=$!
  sleep 1
}
stop_bridge() {
  if [[ -n "$BRIDGE_PID" ]]; then kill "$BRIDGE_PID" 2>/dev/null || true; wait "$BRIDGE_PID" 2>/dev/null || true; fi
  BRIDGE_PID=""
}
cleanup() {
  stop_bridge
  "$HINGE" -d "$UDID" open >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -FyrBridgeEndpoint "127.0.0.1:$PORT" -FyrUITestReset YES \
    -AppleLanguages "($LANGUAGE)" -AppleLocale "${LANGUAGE}_NL" >/dev/null
  sleep 9 # connect, 1.5 s settle, status read, animations
}

# simctl may not write to external volumes directly (privacy), so go via a temp folder.
TMP_SHOTS="$(mktemp -d)"
# The Duo has two built-in displays (class 0): the inner one (widest) and the
# outer one used when closed (narrowest). The default screenshot is the inner one.
OUTER_DISPLAY="$(xcrun simctl io "$UDID" enumerate 2>/dev/null | awk '
  /UUID:/ {uuid=$2} /Display class: 0/ {builtin=1} /Default width:/ { if (builtin) print $3, uuid; builtin=0 }' \
  | sort -n | head -1 | awk '{print $2}')"
SHOT_DISPLAY=""
shoot() {
  local name="$1"
  if [[ -n "$SHOT_DISPLAY" ]]; then
    xcrun simctl io "$UDID" screenshot --display="$SHOT_DISPLAY" "$TMP_SHOTS/$name.png" >/dev/null 2>&1
  else
    xcrun simctl io "$UDID" screenshot "$TMP_SHOTS/$name.png" >/dev/null 2>&1
  fi
  cp "$TMP_SHOTS/$name.png" "$OUT/$name.png"
  echo "$OUT/$name.png"
}

posture() {
  SHOT_DISPLAY=""
  case "$1" in
    open) "$HINGE" -d "$UDID" open ;;
    half) "$HINGE" -d "$UDID" half ;;
    closed) "$HINGE" -d "$UDID" close; SHOT_DISPLAY="$OUTER_DISPLAY" ;;
  esac
  sleep 3
}

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"

  start_bridge --state burning --wave
  for p in open half closed; do
    posture "$p"
    launch
    shoot "duo-$p-$appearance-burning-wave"
  done

  start_bridge --state off --temperature 19.6
  for p in open closed; do
    posture "$p"
    launch
    shoot "duo-$p-$appearance-off"
  done
done

# One English screen for comparison.
LANGUAGE=en
xcrun simctl ui "$UDID" appearance dark
start_bridge --state burning
posture open
launch
shoot "duo-open-dark-burning-en"
