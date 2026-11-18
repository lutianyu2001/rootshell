#!/usr/bin/env bash
# Give the prebuilt frameworks of a resolved package graph an x86_64 iOS
# Simulator slice, so the app builds for the Simulator on an Intel Mac.
#
# usage: sim-x86_64-frameworks.sh <SPM_DIR> <OUT_DIR> <PROJECT.xcodeproj>
#
# <SPM_DIR> is a -clonedSourcePackagesDirPath resolved for this script alone
# (xcodebuild -resolvePackageDependencies): a build that uses the overrides
# removes the overridden packages from its own package directory. Each
# xcframework with an x86_64 Mac Catalyst slice but no x86_64 Simulator slice
# gets the Catalyst x86_64 code re-labelled as iOS Simulator (LC_BUILD_VERSION
# platform 6 -> 7) and merged into its simulator slice; dynamic frameworks also
# get their macOS-style load paths rewritten to the flat iOS ones, and imports
# of macOS-only libSystem variants (_opendir$INODE64) are renamed to the ones
# the Simulator has (macho_imports.py). Swift modules get x86_64 interfaces
# copied from the arm64 Simulator ones. Each package
# so changed is copied to <OUT_DIR>/overrides/<package> with those binary
# targets pointing at the local copies, and <OUT_DIR>/<PROJECT>-sim.xcworkspace
# holds the project and these packages, which override the remote ones. Build
# that workspace for an iOS Simulator destination.
#
# Exits non-zero when a step fails; an xcframework it cannot handle is listed
# as "skip <name>: <reason>". Re-run it after the packages are resolved again
# (a version bump downloads new, arm64-only frameworks).
set -euo pipefail

SPM=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
PROJECT=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
HERE=$(cd "$(dirname "$0")" && pwd)
PY=/usr/bin/python3
TBD=$(xcrun --sdk iphonesimulator --show-sdk-path)/usr/lib/libSystem.B.tbd

STAGE=$OUT/stage
rm -rf "$STAGE" "$OUT/overrides"
mkdir -p "$STAGE" "$OUT/overrides"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Flat iOS path for a macOS-style one: no /System/iOSSupport prefix, no
# Versions/<X>/ inside a framework.
ios_path() {
    sed -E -e 's#^/System/iOSSupport##' -e 's#\.framework/Versions/[^/]+/#.framework/#' <<< "$1"
}

for xcf in "$SPM"/artifacts/*/*/*.xcframework; do
    repo=$(basename "$(dirname "$(dirname "$xcf")")")
    target=$(basename "$xcf" .xcframework)
    read -r kind sim_id sim_bin cat_bin <<< "$("$PY" "$HERE/xcf.py" plan "$xcf")"
    if [ "$kind" = skip ]; then
        echo "skip $repo/$target: $sim_id"
        continue
    fi
    echo "== $repo/$target ($kind)"
    copy=$STAGE/$repo/$target.xcframework
    mkdir -p "$STAGE/$repo"
    cp -R "$xcf" "$copy"
    x86=$WORK/$target.x86_64
    lipo -thin x86_64 "$copy/$cat_bin" -output "$x86"
    if [ "$kind" = framework ]; then
        codesign --remove-signature "$x86" 2> /dev/null || true
        args=(-id "$(ios_path "$(otool -D "$x86" | tail -n 1)")")
        while read -r dep _; do
            new=$(ios_path "$dep")
            [ "$new" = "$dep" ] || args+=(-change "$dep" "$new")
        done < <(otool -L "$x86" | tail -n +3)
        install_name_tool "${args[@]}" "$x86" 2> /dev/null
    fi
    "$PY" "$HERE/macho_platform.py" "$x86" 6 7
    "$PY" "$HERE/macho_imports.py" "$x86" "$TBD"
    lipo -create "$copy/$sim_bin" "$x86" -output "$WORK/fat"
    mv "$WORK/fat" "$copy/$sim_bin"
    # A Swift module gets x86_64 interfaces copied from the arm64 simulator ones.
    for module in "$copy/$(dirname "$sim_bin")"/Modules/*.swiftmodule; do
        [ -d "$module" ] || continue
        for f in "$module"/arm64-apple-ios-simulator.*; do
            g=$module/x86_64-apple-ios-simulator.${f##*/arm64-apple-ios-simulator.}
            case "$f" in
                *.swiftinterface) sed 's/-target arm64-apple-ios/-target x86_64-apple-ios/' "$f" > "$g" ;;
                *) cp "$f" "$g" ;;
            esac
        done
    done
    if [ "$kind" = framework ]; then
        # Weak loads may be missing at run time; any other difference is worth a look.
        diff <(otool -arch arm64 -L "$copy/$sim_bin" | tail -n +2 | grep -v ', weak)' | awk '{print $1}' | sort) \
             <(otool -arch x86_64 -L "$copy/$sim_bin" | tail -n +2 | grep -v ', weak)' | awk '{print $1}' | sort) \
            > "$WORK/deps.diff" || { echo "  load paths differ between arm64 and x86_64:"; sed 's/^/  /' "$WORK/deps.diff"; }
        codesign -f -s - "$copy/$(dirname "$sim_bin")" > /dev/null 2>&1
    fi
    "$PY" "$HERE/xcf.py" addx86 "$copy" "$sim_id"
done

packages=()
for stage in "$STAGE"/*; do
    [ -d "$stage" ] || continue
    repo=$(basename "$stage")
    dest=$OUT/overrides/$repo
    rsync -a --exclude .git "$SPM/checkouts/$repo/" "$dest/"
    chmod -R u+w "$dest"   # SwiftPM checks packages out read-only
    mkdir -p "$dest/xcframeworks"
    targets=()
    for copy in "$stage"/*.xcframework; do
        targets+=("$(basename "$copy" .xcframework)")
        mv "$copy" "$dest/xcframeworks/"
    done
    "$PY" "$HERE/xcf.py" package "$dest/Package.swift" "${targets[@]}"
    packages+=("$dest")
done
rm -rf "$STAGE"

WORKSPACE=$OUT/$(basename "$PROJECT" .xcodeproj)-sim.xcworkspace
[ ${#packages[@]} -gt 0 ] || { echo "no xcframework needed an x86_64 Simulator slice" >&2; exit 1; }
"$PY" "$HERE/xcf.py" workspace "$WORKSPACE" "$PROJECT" "${packages[@]}"
echo "workspace: $WORKSPACE (${#packages[@]} packages overridden)"
