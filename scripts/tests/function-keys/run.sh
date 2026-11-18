#!/usr/bin/env bash
# Build and run the function-key test: with swiftc when it is installed,
# otherwise in the swift:6.0-noble container through podman or docker.
set -eu
cd "$(dirname "$0")"
./build.sh "$@"
cmd='swiftc -O FKeyTest.swift -o fkeytest && ./fkeytest'
if command -v swiftc > /dev/null; then
  sh -c "$cmd"
else
  engine=$(command -v podman || command -v docker)
  "$engine" run --rm -v "$PWD":/t:Z -w /t docker.io/library/swift:6.0-noble sh -c "$cmd"
fi
