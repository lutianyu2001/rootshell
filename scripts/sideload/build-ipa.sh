#!/bin/bash
# Build an Xcode app's IPA, signed ad hoc only, for installing with SideStore under a free Apple ID,
# with render-entitlements.py beside it.
#
# The arrays expand as ${A[@]+"${A[@]}"}: macOS's bash 3.2 calls an empty array unbound under set -u.
#
# Usage: scripts/sideload/build-ipa.sh <DERIVED_DATA_DIR> <OUTPUT_IPA> [<PACKAGES_DIR>]
#
# Package downloads authenticate from ~/.netrc when it has api.github.com: unauthenticated,
# GitHub's API refuses (403) the binary targets' downloads once its rate limit is reached.
set -euo pipefail

# Per project: the project, the scheme and the configuration that build the app for devices, and
# the app's name (its .app in the build products).
PROJECT=rootshell.xcodeproj
SCHEME=rootshell-AppStore
CONFIGURATION=ReleaseAppStore
APP_NAME=rootshell
# Per project: the extensions a free Apple ID cannot sign (a packet tunnel, push notifications):
# they could not work, and each would use one of its ten App IDs a week.
DROP_EXTENSIONS=(VPNTunnelExtension PushNotificationService)
# Per project: the entitlements to sign with, the app's, then each extension it keeps as
# <path inside the .app>=<entitlements file>.
APP_ENTITLEMENTS=rootshell/Entitlements/AppStore.entitlements
EXTENSION_ENTITLEMENTS=("PlugIns/SessionActivityWidgetExtension.appex=SessionActivityWidget/SessionActivityWidget.entitlements")

if [ $# -lt 2 ]; then
  echo "usage: $0 <DERIVED_DATA_DIR> <OUTPUT_IPA> [<PACKAGES_DIR>]" >&2
  exit 2
fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1" "$(dirname "$2")"
DD=$(cd "$1" && pwd)
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
PKG=${3:-$DD/packages}
XCODE_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION"
  -destination generic/platform=iOS -packageAuthorizationProvider netrc)

cd "$ROOT"
xcodebuild "${XCODE_ARGS[@]}" -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$PKG" \
  CODE_SIGNING_ALLOWED=NO build

APP=$DD/Build/Products/$CONFIGURATION-iphoneos/$APP_NAME.app
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
SIGNED=$STAGE/Payload/$APP_NAME.app
for ext in ${DROP_EXTENSIONS[@]+"${DROP_EXTENSIONS[@]}"}; do
  rm -rf "$SIGNED/PlugIns/$ext.appex"
done

# Sign ad hoc with the entitlements the app asks for (an app group above all), filled in from the
# build settings: SideStore reads them from the signature to know what to request when it
# re-signs, and an unsigned app asks for nothing.
xcodebuild "${XCODE_ARGS[@]}" -showBuildSettings -json 2>/dev/null > "$STAGE/settings.json"
render() { python3 "$ROOT/scripts/sideload/render-entitlements.py" "$STAGE/settings.json" "$1" "$2"; }
codesign --force --deep -s - "$SIGNED"
i=0
for pair in ${EXTENSION_ENTITLEMENTS[@]+"${EXTENSION_ENTITLEMENTS[@]}"}; do
  render "${pair#*=}" "$STAGE/ext$i.entitlements"
  codesign --force -s - --entitlements "$STAGE/ext$i.entitlements" "$SIGNED/${pair%%=*}"
  i=$((i + 1))
done
render "$APP_ENTITLEMENTS" "$STAGE/app.entitlements"
codesign --force -s - --entitlements "$STAGE/app.entitlements" "$SIGNED"
codesign --verify --deep "$SIGNED"

rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" Payload)
echo "$OUT"
