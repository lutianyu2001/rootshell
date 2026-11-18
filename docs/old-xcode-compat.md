# Building with an older Xcode

This fork's main builds with Xcode 26.3, on a Mac that cannot run the Xcode
upstream needs. It was made on an Intel Mac mini (2018, Macmini8,1) with macOS
15.8.3, Xcode 26.3 (17C529), the iOS 26.2 SDK and Swift 6.2.4. Upstream needs
Xcode 27.1 (the iOS 27.1 SDK), which requires macOS Tahoe 26.6 or later; main
gives up the iPhone Duo hinge and fold support instead, which this fork does not
use. The changes came from the branch `compat/xcode-26.3`.

What builds there: the sandboxed Mac Catalyst app (`rootshell-AppStore`),
unsigned, which then runs on that Mac, and the iOS Simulator app, with the
prebuilt frameworks relabelled for x86_64 (see below). What does not: iOS
device builds (they need a signing team).

- **Merging upstream into main:** upstream keeps adding code for the iOS 27.1
  SDK. After each merge, build with Xcode 26.3 and wrap whatever new code fails
  the way the next section says.
- **A branch meant for upstream** starts from `upstream`, which has none of these
  changes, so it does not build with Xcode 26.3 by itself. To build or test it
  on the old Xcode, merge it into a throwaway branch cut from main. Where it also
  edits the README's Xcode line, keep main's line.

## What main changes, and why

Each item was a compile or launch failure with the versions above.

- **iOS 27.1 SDK APIs.** Code for the iPhone Duo hinge and fold calls APIs the
  iOS 26.2 SDK does not have (the first error was `reservedRegions(kind:)` on
  `GeometryProxy`; others are `UIHingeInteraction` and the vertical bar
  configuration). `#available(iOS 27.1, *)` does not help:
  the symbols must exist at compile time. Every `if #available(iOS 27.1` block and
  `@available(iOS 27.1` declaration is wrapped in
  `#if false // Needs the iOS 27.1 SDK`; an `else` branch is kept as a `do`
  block, and a `guard #available(iOS 27.1` returns its fallback. When upstream
  adds more such code, search for `iOS 27.1` and wrap it the same way.
- **Memberwise initializers.** Swift 6.2 makes a struct's memberwise
  initializer private when a stored property is private, even one with a
  default value, so `KVMPaneRootView(pane:)` and `VNCPaneRootView(pane:)` failed
  with "initializer is inaccessible due to 'private' protection level". Both
  get an explicit `init(pane:)`.
- **Type-checking time.** Swift 6.2 gives up on the long modifier chain of
  `SSHConnectionView.navigationStackContent` ("unable to type-check this
  expression in reasonable time"). It is split into three properties.
- **Optimizer crash.** In a release build (`scripts/sideload/build-ipa.sh`), Swift
  6.2's EarlyPerfInliner crashes on the implicit deinit of the generic
  `SwiftUIBannerHostView` ("While running pass ... EarlyPerfInliner on
  SILFunction ...SwiftUIBannerHostViewCfD"). The class has an explicit
  `@_optimize(none) deinit {}`. Debug builds do not optimize and never hit it.
  The release build's whole-module optimization then runs as one compiler
  process for tens of minutes with no output; it is not stuck while that
  process uses CPU.
- **Newer Xcode 26.x too.** Main also has to build with the Xcode 26 releases
  after 26.3: GitHub's macOS runners default to the newest (26.6 on
  2026-11-17). Xcode 26.6's type checker gave up on the optical depth step of
  `WeatherSkyGeometry.sunTransmittance` written as one expression ("unable to
  type-check this expression in reasonable time"), which 26.3 compiles; it is
  split into typed parts, the same terms in the same order. The fork's CI and
  release pin Xcode 26.3 (`DEVELOPER_DIR` in `.github/workflows/`), as on the
  Mac mini, and the runners keep 26.0 to 26.6 side by side.
- **Metal Toolchain.** Xcode 26.3 does not ship the Metal compiler; the build
  fails with "cannot execute tool 'metal' due to missing Metal Toolchain".
  Install it once with `xcodebuild -downloadComponent MetalToolchain` (about
  700 MB; Xcode 26.3 installs build 17C7003j). For an offline copy, add
  `-exportPath <DIR> -buildVersion 17C7003j`, which writes
  `MetalToolchain-17C7003j.exportedBundle`; install that later with
  `xcodebuild -importComponent MetalToolchain -importPath <BUNDLE>`.

## The iOS Simulator on an Intel Mac

On an Intel Mac the Simulator runs x86_64, and the prebuilt frameworks have
only an arm64 simulator slice (GhosttyKit, HelixKit, ios_system, vim, curl and
others). Every one of them has an x86_64 Mac Catalyst slice, though, and that
code runs in the Simulator once it is labelled for it.
`scripts/old-xcode/build-simulator.sh <WORK_DIR> <SIMULATOR_UDID>` does it all:

- It resolves the packages into `<WORK_DIR>/spm-pristine`, which only the
  relabelling reads: a build with the overrides removes the overridden packages
  from its own package directory.
- `x86_64-simulator/sim-x86_64-frameworks.sh` takes each xcframework without an
  x86_64 Simulator slice, sets the platform of the Catalyst x86_64 code from Mac
  Catalyst (6) to iOS Simulator (7) in every `LC_BUILD_VERSION`
  (`macho_platform.py`), and merges it into the Simulator slice. Dynamic
  frameworks also get their macOS load paths made flat (`Versions/A/`,
  `/System/iOSSupport` dropped), and a Swift module gets x86_64 interfaces copied
  from the arm64 Simulator ones.
- macOS headers pick variants such as `_opendir$INODE64` that the Simulator's
  libSystem does not export (64-bit inodes are the iOS default, so `_opendir`
  is the same function). `macho_imports.py` renames those imports in place, in
  symbol tables, chained fixups and dyld bind opcodes alike; variants the
  Simulator has (`_realpath$DARWIN_EXTSN`, `_select$1050`) stay.
- Each changed package is copied to `<WORK_DIR>/sim/overrides/<package>` with
  its binary targets pointing at the local copies, and
  `<WORK_DIR>/sim/rootshell-sim.xcworkspace` holds the project and these
  packages, which override the remote ones. The script builds that workspace.
- `MainThreadStackSampler` reads ARM registers, so it gets the Catalyst stub on
  x86_64 too.

On 2026-11-17 this covered 18 xcframeworks in 13 packages and the app built
and ran in an iPhone 17 Pro Simulator (iOS 26.3). Re-run the script after a
package update, which brings new arm64-only frameworks.

What the Simulator cannot do there: a terminal. The Simulator renders Metal on
the Mac's GPU, and on the Mac mini's Intel UHD 630 the Metal Simulator fails on
Ghostty's workload ("encountered a fatal error while deserializing or
re-encoding a Metal Simulator workload"); SimMetalHost aborts and the app dies.
Screens without a terminal work: settings, connection sheets, and the keyboard
toolbar above the system keyboard, which the SSH tab's Quick Connect field
shows. Test the terminal itself in the Catalyst app, which renders on the real
GPU.

The keyboard toolbar does not exist in the Catalyst app: macOS shows no input
accessory views, and the setting that keeps the toolbar with a hardware
keyboard is compiled out there.

## Driving the Simulator with idb

idb taps and reads a Simulator's UI, but its releases (v1.7.8) ship an arm64
`idb_companion` only, and Homebrew does not build it from source.
`scripts/old-xcode/build-idb.sh <WORK_DIR>` builds it for x86_64: it clones
v1.7.8, builds XcodeGen with SwiftPM and fetches protobuf's x86_64 `protoc`,
patches idb (`x86_64-simulator/patch-idb.py`: `ARCHS=x86_64`, x86_64 in the
private framework stubs, two closures Swift 6.2.4 rejects), and builds the
companion, its shims and the simulator bridge.

Then start the companion and install the client:

```bash
<WORK_DIR>/idb/Build/Products/Release/idb_companion --udid <SIMULATOR_UDID> --grpc-port 10882 &
pip install fb-idb
scripts/old-xcode/simtap.py --list          # labels and frames of what is on screen
scripts/old-xcode/simtap.py <LABEL>...       # tap elements by accessibility label, in order
```

`keyecho_sshd.py <PORT> <LOG>` is an SSH server (paramiko) that accepts any
login and echoes, in visible form (`^[OP`), every byte the terminal sends, so a
key press can be checked against the sequence it should send.

To set a setting before launch, edit the plist in the app's data container
(`xcrun simctl get_app_container <UDID> com.kk2.rootshell data`, then
`Library/Preferences/com.kk2.rootshell.plist`) while the app is not running;
`simctl spawn defaults write` writes the Simulator's global domain, which the
app does not read.

## Running an unsigned build

`scripts/old-xcode/build-catalyst.sh <DERIVED_DATA_DIR>` builds the app and
signs it ad hoc. What it works around:

- **Sandbox.** Unsigned, the app runs without the sandbox, finds its config
  file under the real `~/Documents`, and macOS asks for permission to that
  folder. The prompt blocks the main thread (`ConfigOverlayManager` opening the
  directory), so no window appears. The script signs the app ad hoc with
  `test-sandbox.entitlements` (sandbox and network only), which keeps its files
  in its container.
- **Restricted entitlements.** iCloud, keychain groups and push need a
  provisioning profile, so an ad hoc signature cannot carry them. Without the
  iCloud entitlement `CKContainer(identifier:)` traps (SIGILL) at launch; the
  code creates the container on first use and skips the launch-time CloudKit
  calls when `ROOTSHELL_TEST_NO_CLOUDKIT=1`.

## Test switches

Each is off unless its environment variable is `1`. Pass them with
`open -n --env NAME=1 <APP>`.

| Variable | Effect |
|---|---|
| `ROOTSHELL_TEST_TRUST_ALL_HOSTKEYS` | SSH tabs accept any host key. They validate in `CitadelHostKeyValidatorDelegate`; `SSHHostKeyDelegate` is a different path. |
| `ROOTSHELL_TEST_NO_CLOUDKIT` | Skips the CloudKit calls at launch. |
| `ROOTSHELL_TEST_CONNECT_URL` | An `ssh://` URL without history connects at once instead of opening the connection sheet. |

## The reconnect test

`scripts/old-xcode/reconnect-test.sh <APP> <WORK_DIR>` checks that a dropped
SSH connection leaves no remote input modes behind. It needs no clicks:
`fake_sshd.py` (paramiko, installed into `<WORK_DIR>/venv`) accepts any login,
turns on mouse reporting (1000, 1002, 1006), focus reporting (1004), bracketed
paste (2004) and the alternate screen (1049) on the first connection, checks
with DECRQM that the terminal took them, and drops the TCP connection without
an exit status. rootshell reconnects, and on the second connection the server
asks again. It exits 0 when every mode answers 2 (reset).

On 2026-11-17, with Xcode 26.3 on the Mac mini above, the build with the fix of
`fix/reset-modes-on-disconnect` passed (every mode reset after the reconnect),
and the same build without it failed: 1000, 1002, 1006, 1004, 2004 and 1049
were all still set on the reconnected shell, so a mouse move there sends
reports the shell prints as raw escape sequences.

Each run connects as a new random user (`tester<N>`): once a host and user are
in the connection history, an `ssh://` URL takes the history path, which opens
the connection sheet, and the test would wait for a click.

## Working on the Mac over SSH

- `screencapture` run over SSH needs Screen Recording for
  `/usr/libexec/sshd-keygen-wrapper`. Without it, it fails silently and captures
  only the wallpaper and the menu bar, which looks like an app with no window.
  The grant can be written into the system TCC database only with SIP off.
- To see whether the app has windows without a screenshot, list them with
  `CGWindowListCopyWindowInfo` for its PID; to see where it is stuck,
  `sample <PID> 1`.
- The launched app's environment shows in `ps eww -p <PID>`.
