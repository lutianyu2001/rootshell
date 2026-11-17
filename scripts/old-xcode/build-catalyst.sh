#!/bin/zsh
# Build the sandboxed Mac Catalyst app with Xcode 26.3, unsigned, then sign it
# ad hoc with the sandbox entitlements only. See docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/build-catalyst.sh <DERIVED_DATA_DIR> [<PACKAGES_DIR>]
# Prints the app's path on the last line.
set -eu
if [ $# -lt 1 ]; then
  echo "usage: $0 <DERIVED_DATA_DIR> [<PACKAGES_DIR>]" >&2
  exit 2
fi
HERE=${0:A:h}
ROOT=${HERE:h:h}
DD=${1:A}
PKG=${2:-$DD/packages}

cd $ROOT
xcodebuild -project rootshell.xcodeproj -scheme rootshell-AppStore \
  -destination "platform=macOS,variant=Mac Catalyst" \
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$PKG" \
  CODE_SIGNING_ALLOWED=NO build

APP=$(ls -d "$DD"/Build/Products/*-maccatalyst/rootshell.app | head -1)
# Unsandboxed, the app asks for ~/Documents and blocks its main thread on the
# prompt; the restricted entitlements (iCloud, keychain groups) need a profile.
codesign --force --deep -s - "$APP"
codesign --force -s - --entitlements "$HERE/test-sandbox.entitlements" "$APP"
echo "$APP"
