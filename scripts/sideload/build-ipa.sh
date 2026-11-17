#!/bin/bash
# Build a rootshell IPA, signed ad hoc only, for installing with SideStore
# under a free Apple ID. See docs/sideload.md.
#
# Usage: scripts/sideload/build-ipa.sh <DERIVED_DATA_DIR> <OUTPUT_IPA> [<PACKAGES_DIR>]
set -euo pipefail
if [ $# -lt 2 ]; then
  echo "usage: $0 <DERIVED_DATA_DIR> <OUTPUT_IPA> [<PACKAGES_DIR>]" >&2
  exit 2
fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1" "$(dirname "$2")"
DD=$(cd "$1" && pwd)
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
PKG=${3:-$DD/packages}

cd "$ROOT"
xcodebuild -project rootshell.xcodeproj -scheme rootshell-AppStore -configuration ReleaseAppStore \
  -destination generic/platform=iOS -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$PKG" \
  CODE_SIGNING_ALLOWED=NO build

APP=$DD/Build/Products/ReleaseAppStore-iphoneos/rootshell.app
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
# A free Apple ID can sign neither a packet tunnel nor push, so these two
# extensions could not work, and each would use one of its ten App IDs a week.
rm -rf "$STAGE/Payload/rootshell.app/PlugIns/VPNTunnelExtension.appex" \
  "$STAGE/Payload/rootshell.app/PlugIns/PushNotificationService.appex"
# Sign ad hoc with the entitlements the app asks for (the app group above all),
# filled in from the build settings: SideStore reads them from the signature to
# know what to request when it re-signs, and an unsigned app asks for nothing.
xcodebuild -project rootshell.xcodeproj -scheme rootshell-AppStore -configuration ReleaseAppStore \
  -destination generic/platform=iOS -showBuildSettings -json 2>/dev/null > "$STAGE/settings.json"
python3 "$ROOT/scripts/sideload/render-entitlements.py" "$STAGE/settings.json" \
  rootshell/Entitlements/AppStore.entitlements "$STAGE/app.entitlements"
python3 "$ROOT/scripts/sideload/render-entitlements.py" "$STAGE/settings.json" \
  SessionActivityWidget/SessionActivityWidget.entitlements "$STAGE/widget.entitlements"
SIGNED=$STAGE/Payload/rootshell.app
codesign --force --deep -s - "$SIGNED"
codesign --force -s - --entitlements "$STAGE/widget.entitlements" \
  "$SIGNED/PlugIns/SessionActivityWidgetExtension.appex"
codesign --force -s - --entitlements "$STAGE/app.entitlements" "$SIGNED"
codesign --verify --deep "$SIGNED"

rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" Payload)
echo "$OUT"
