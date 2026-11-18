#!/bin/zsh
# Build idb_companion, the iOS Simulator automation server, for an Intel Mac
# with Xcode 26.3. idb releases ship arm64 only and Homebrew cannot build it;
# see docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/build-idb.sh <WORK_DIR>
# Clones idb v1.7.8 into <WORK_DIR>/idb, builds its tools (XcodeGen with
# SwiftPM, protobuf's own x86_64 protoc) under <WORK_DIR>/tools, patches idb
# (x86_64/patch-idb.py) and builds the companion, its shims and the simulator
# bridge. Prints the companion's path on the last line. Re-running continues
# where it stopped.
set -eu
HERE=${0:A:h}
W=${1:A}
mkdir -p $W/tools
cd $W
[ -d idb ] || git clone -q --depth 1 --branch v1.7.8 https://github.com/facebook/idb.git
if [ ! -x tools/xcodegen/.build/release/xcodegen ]; then
  [ -d tools/xcodegen ] || git clone -q --depth 1 --branch 2.47.0 https://github.com/yonaskolb/XcodeGen.git tools/xcodegen
  (cd tools/xcodegen && swift build -c release --disable-sandbox)
fi
if [ ! -x tools/protoc/bin/protoc ]; then
  tag=$(curl -sS https://api.github.com/repos/protocolbuffers/protobuf/releases/latest |
    /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')
  curl -sSL -o protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/$tag/protoc-${tag#v}-osx-x86_64.zip"
  mkdir -p tools/protoc && unzip -q -o protoc.zip -d tools/protoc && rm protoc.zip
fi
export PATH=$W/tools/protoc/bin:$W/tools/xcodegen/.build/release:$PATH
/usr/bin/python3 $HERE/x86_64-simulator/patch-idb.py idb
cd idb
for target in idb_companion shims SimulatorFrameworkBridge-iOS; do
  ./build.sh build $target
done
echo $W/idb/Build/Products/Release/idb_companion
