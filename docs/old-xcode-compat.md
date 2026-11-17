# Building with an older Xcode

The branch `compat/xcode-26.3` builds rootshell with Xcode 26.3 on a Mac that
cannot run the Xcode the project needs. It was made on an Intel Mac mini (2018,
Macmini8,1) with macOS 15.8.3, Xcode 26.3 (17C529), the iOS 26.2 SDK and Swift
6.2.4. The project itself needs Xcode 27.1 (the iOS 27.1 SDK), which requires
macOS Tahoe 26.6 or later.

What builds there: the sandboxed Mac Catalyst app (`rootshell-AppStore`),
unsigned, which then runs on that Mac. What does not: iOS device builds (they
need a signing team) and the iOS Simulator (see below).

The branch never goes upstream. Bring upstream into it by merging `upstream`;
to test a change, merge its branch into a throwaway branch cut from this one.
A branch that also edits the README's Xcode line conflicts there; keep this
branch's line.

## What the branch changes, and why

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
- **Metal Toolchain.** Xcode 26.3 does not ship the Metal compiler; the build
  fails with "cannot execute tool 'metal' due to missing Metal Toolchain".
  Install it once with `xcodebuild -downloadComponent MetalToolchain` (about
  700 MB; Xcode 26.3 installs build 17C7003j). For an offline copy, add
  `-exportPath <DIR> -buildVersion 17C7003j`, which writes
  `MetalToolchain-17C7003j.exportedBundle`; install that later with
  `xcodebuild -importComponent MetalToolchain -importPath <BUNDLE>`.

## Why Mac Catalyst and not the Simulator

On an Intel Mac the Simulator runs x86_64, and the prebuilt frameworks have
only an arm64 simulator slice (GhosttyKit, HelixKit, ios_system, vim, curl and
others), so the app fails to link. `MainThreadStackSampler` also reads ARM
registers and only compiles on arm64. Every framework has an x86_64 Mac
Catalyst slice, and the terminal and reconnect code is shared, so the Catalyst
app exercises the same paths.

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
  branch creates the container on first use and skips the launch-time CloudKit
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
- To see whether the app has windows without a screenshot, list them with
  `CGWindowListCopyWindowInfo` for its PID; to see where it is stuck,
  `sample <PID> 1`.
- The launched app's environment shows in `ps eww -p <PID>`.
