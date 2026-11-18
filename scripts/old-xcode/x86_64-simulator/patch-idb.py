#!/usr/bin/env python3
"""Patch a checkout of facebook/idb v1.7.8 so it builds for x86_64 with Xcode 26.3.

usage: patch-idb.py <IDB_CHECKOUT>

idb ships and builds arm64 only, against Xcode 26.5. Each patch is applied once
(already patched files are left alone); the script fails when a file no longer
looks as expected, e.g. after a new idb release.

- build.sh: ARCHS=arm64 -> ARCHS=x86_64.
- PrivateHeaders/*/*.tbd: the stubs list only arm64-macos; the real frameworks on
  an Intel Mac have x86_64.
- Two Task closures capture a nonisolated(unsafe) local, which Swift 6.2.4
  rejects ("passing closure as a 'sending' parameter risks causing data
  races"); they capture an @unchecked Sendable box instead.
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        return
    if s.count(old) != 1:
        sys.exit(f"{rel}: expected text not found once; idb changed, update this script")
    p.write_text(s.replace(old, new))
    print(f"patched {rel}")


patch("build.sh", "    ARCHS=arm64\n", "    ARCHS=x86_64\n")

for tbd in sorted(root.glob("PrivateHeaders/*/*.tbd")):
    s = tbd.read_text()
    if "x86_64-macos" not in s:
        tbd.write_text(s.replace("[ arm64-macos ]", "[ x86_64-macos, arm64-macos ]"))
        print(f"patched {tbd.relative_to(root)}")

patch("FBSimulatorCodeInjection/ControlSocketClient.swift",
      """    nonisolated(unsafe) let commandHandler = handler
    Task {
      box.value = await commandHandler(commandData)""",
      """    // Xcode 26.3's Swift 6.2.4 rejects capturing a nonisolated(unsafe) local here.
    final class HandlerBox: @unchecked Sendable {
      let handler: HostCommandHandler
      init(_ handler: @escaping HostCommandHandler) { self.handler = handler }
    }
    let commandHandler = HandlerBox(handler)
    Task {
      box.value = await commandHandler.handler(commandData)""")

patch("Companion/main.swift",
      """    nonisolated(unsafe) let target = target
    raceTasks.append(Task { try await awaitTargetOffline(target, logger: logger) })""",
      """    let targetBox = UncheckedSendableBox(target)
    raceTasks.append(Task { try await awaitTargetOffline(targetBox.value, logger: logger) })""")
main = root / "Companion/main.swift"
if "class UncheckedSendableBox" not in main.read_text():
    with main.open("a") as f:
        f.write("""
// Xcode 26.3's Swift 6.2.4 rejects capturing a nonisolated(unsafe) local in a Task.
private final class UncheckedSendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}
""")
