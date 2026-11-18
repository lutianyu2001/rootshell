#!/bin/zsh
# Build the app for the iOS Simulator on an Intel Mac with Xcode 26.3, whose
# Simulator runs x86_64 while the prebuilt frameworks ship an arm64 Simulator
# slice only. See docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/build-simulator.sh <WORK_DIR> <SIMULATOR_UDID>
# <WORK_DIR> keeps spm-pristine/ (packages resolved for the retagging alone),
# sim/ (the retagged packages and the workspace that overrides them), spm/
# (the build's packages) and dd/ (DerivedData); re-running reuses them.
# Prints the app's path on the last line.
set -eu
HERE=${0:A:h}
ROOT=${HERE:h:h}
W=${1:A}
UDID=$2
mkdir -p $W
cd $ROOT
xcodebuild -resolvePackageDependencies -project rootshell.xcodeproj -scheme rootshell-AppStore \
  -clonedSourcePackagesDirPath $W/spm-pristine
$HERE/x86_64-simulator/sim-x86_64-frameworks.sh $W/spm-pristine $W/sim $ROOT/rootshell.xcodeproj
xcodebuild -workspace $W/sim/rootshell-sim.xcworkspace -scheme rootshell-AppStore -configuration DebugAppStore \
  -destination "id=$UDID" -derivedDataPath $W/dd -clonedSourcePackagesDirPath $W/spm build
ls -d $W/dd/Build/Products/DebugAppStore-iphonesimulator/rootshell.app
