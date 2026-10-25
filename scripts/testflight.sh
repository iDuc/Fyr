#!/usr/bin/env bash
# Archive Fyr and upload it to TestFlight (internal testing only).
#
#   scripts/testflight.sh archive   # archive + export IPA, no upload
#   scripts/testflight.sh upload    # archive + upload to App Store Connect
#
# On SloerieServer run it inside a heavy reservation:
#   sloerie-simulators run --heavy --device duo --agent <agent> --task "Fyr TestFlight" -- scripts/testflight.sh upload
#
# Needs the App Store Connect app record for com.vanYperen.Fyr (the API cannot
# create it). Credentials come from scripts/asc_api.py's sources and are never
# printed: key QSKWP2WVYV next to the projects, issuer from ASC_ISSUER_ID or
# KeepOfEchoes/.env.release.
set -euo pipefail

ACTION="${1:-archive}"
case "$ACTION" in archive | upload) ;; *) echo "usage: $0 archive|upload" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="/Volumes/ThunderSloerie/BuildArtifacts/Fyr"
DERIVED="$ARTIFACTS/DerivedData"
DEV="/Volumes/ThunderSloerie/Development"
KEY_ID="${ASC_KEY_ID:-QSKWP2WVYV}"
KEY_PATH="${ASC_KEY_PATH:-$DEV/AuthKey_${KEY_ID}.p8}"
if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
  ASC_ISSUER_ID="$(grep -E '^ASC_ISSUER_ID=' "$DEV/KeepOfEchoes/.env.release" | head -1 | cut -d= -f2- | tr -d "\"'")"
fi
[[ -f "$KEY_PATH" && -n "$ASC_ISSUER_ID" ]] || { echo "App Store Connect key or issuer missing" >&2; exit 1; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Build number: UTC timestamp, always increasing.
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
VERSION="$(grep -m1 'MARKETING_VERSION = ' "$ROOT/Fyr.xcodeproj/project.pbxproj" | sed -E 's/.*= ([^;]+);/\1/')"
NAME="Fyr-$VERSION-$BUILD_NUMBER"
ARCHIVE="$ARTIFACTS/archives/$NAME.xcarchive"
EXPORT="$ARTIFACTS/export/$NAME"
LOG="$ARTIFACTS/logs/$NAME"
mkdir -p "$ARTIFACTS/archives" "$ARTIFACTS/export" "$LOG"

AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "Archiving Fyr $VERSION ($BUILD_NUMBER)…"
xcodebuild archive -project "$ROOT/Fyr.xcodeproj" -scheme Fyr -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" -jobs 2 \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${AUTH[@]}" > "$LOG/archive.log" 2>&1 \
  || { tail -30 "$LOG/archive.log"; exit 1; }

DESTINATION=export
[[ "$ACTION" == "upload" ]] && DESTINATION=upload
cat > "$LOG/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>SZWSVWQSP3</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
PLIST

echo "Exporting ($DESTINATION)…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$LOG/ExportOptions.plist" "${AUTH[@]}" > "$LOG/export.log" 2>&1 \
  || { tail -30 "$LOG/export.log"; exit 1; }

echo "Archive: $ARCHIVE"
echo "Export:  $EXPORT"
echo "Build:   $VERSION ($BUILD_NUMBER)"
