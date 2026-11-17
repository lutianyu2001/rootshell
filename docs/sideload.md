# Installing with SideStore

This fork is installed on iPhone and iPad with [SideStore](https://sidestore.io), which signs the app under a free
Apple ID. Each release carries a `rootshell-<version>-ios.ipa` for it, signed ad hoc only: the signature carries the
entitlements the app asks for, which SideStore reads to know what to request when it re-signs.

## Getting the IPA

- **From a release:** pushing a tag `v<version>` runs `.github/workflows/release.yml` on a macOS runner, which
  builds the IPA with `scripts/sideload/build-ipa.sh` and attaches it to the GitHub release. The fork's tags follow
  upstream's next version plus `-mod.X.Y`, for example `v1.0.17-mod.1.1` (only an example); the app itself keeps
  upstream's version number, since iOS takes digits only there.
- **By hand, on a Mac:** `scripts/sideload/build-ipa.sh <DERIVED_DATA_DIR> <OUTPUT_IPA>`. It needs Xcode 26.3 or
  later with the Metal Toolchain (`docs/old-xcode-compat.md`).

Open the IPA in SideStore to install it. A free Apple ID's signature lasts 7 days, so SideStore refreshes the app
before then, and it allows three apps at a time, SideStore included.

## What a free Apple ID cannot sign, and what this build does about it

The build is the App Store configuration with `SIDELOAD` set (`Configuration/AppStore.xcconfig`).

| Capability | In this build |
|---|---|
| iCloud (CloudKit sync) | Entitlement removed; sync stays off and cannot be turned on. Creating the CloudKit container without the entitlement traps at launch. |
| Push notifications | Entitlement removed; the push notification service extension is left out of the IPA. |
| VPN (packet tunnel) | Entitlement removed; the VPN tunnel extension is left out of the IPA. The VPN screens remain, and fail to connect. |
| Associated domains, multicast | Entitlements removed. |
| Keychain sharing | SideStore signs with its own team prefix, so the app asks the keychain which access group it was signed with instead of using the team in Info.plist. |
| App groups | Kept, for the Live Activity widget; code that uses the group falls back when it is missing. |

The other entitlements (NFC, smart cards, Wi-Fi information, multipath, user fonts) are kept; a signer that cannot
grant one leaves it out, and that feature fails at run time.

What a free Apple ID allows has no official list; the table follows what SideStore's users report. Check on a device
after installing: that the app launches, that a saved SSH key or password survives a restart of the app (the
keychain group), and that a Live Activity appears for a session.
