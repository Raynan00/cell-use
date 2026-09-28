# Set up the iPhone demo

## Requirements

- The current native demo targets iOS 27.0 and a physical iPhone. The demo is built with Xcode 27.
- Developer Mode enabled, pairing completed and the matching personalized
  developer image/services prepared. Installing the app alone does not do this.
- LocalDevVPN enabled and its **Device IP** available. The tested configuration
  was Device IP `10.7.0.1/32`, Tunnel IP `10.7.1.1/32`; use your app's actual values.
- An unlocked phone, Wi-Fi, local-network permission and portrait rotation lock.
- A signing route: Xcode on a Mac, or an unsigned release IPA signed with a tool
  such as Sideloadly on Windows. Development used a free Apple account; signing
  renewal and the requirements of your signing tool still apply.

LocalDevVPN is a separate app, not included in cell-use:
[App Store listing](https://apps.apple.com/us/app/localdevvpn/id6755608044).
The tunnel routes same-device developer-service traffic.
The current native transport explicitly requires Developer Mode.

## Install

Download `cell-use-demo-unsigned.ipa` and `SHA256SUMS` from a GitHub prerelease.
Compare the archive's SHA-256 with the published checksum before signing.
The IPA is unsigned and cannot be installed directly.

On Windows, install/trust the phone through Apple's device software, then use
[Sideloadly](https://sideloadly.io/) to sign/install the archive with your own
account. Follow its signing and device-trust prompts. Never share signing or
pairing credentials in a GitHub issue.

If signing changes the bundle identifier, the continued-processing task wildcard
must match the **final signed identifier**. The helper below edits a copy of the
unsigned archive's Info.plist before you sign it:

```sh
python3 Scripts/configure-background-identifier.py --help
```

Choose the final identifier in your signing tool, use that same identifier with
the helper, then sign the resulting archive. A mismatched wildcard prevents the
extended test from registering. Normal tests and the report expose this separately.
No personalized archive or Apple identifier is distributed with the release.

If building on Mac instead, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig`, set your bundle identifier/team, run the build script,
and open `CellUseDemo.xcodeproj` to sign and run. Ensure the permitted background
task identifier in Info.plist matches your chosen bundle identifier plus `.probe.*`.

## Prepare developer services

Use Xcode's device preparation with a version supporting your iOS release.
The Windows development setup used pymobiledevice3 to install the matching
personalized Cryptex1 developer image. That is a separate preparation step and
is OS/tool-version dependent; consult its [upstream documentation](https://github.com/doronz88/pymobiledevice3).
Complete device preparation before starting a native session.

## Pair and connect

1. Open cell-use and tap **Pair this iPhone**. Allow local-network access.
2. Open Settings → Privacy & Security → Developer Mode and select the advertised
   cell-use host. Enter the code shown by the app/notification. Return promptly;
   ordinary background time during pairing is limited.
3. Enable LocalDevVPN. In cell-use select the local VPN route and enter its
   Device IP (without `/32` if the field expects an address). Keep port `49152`
   unless your setup specifies a different endpoint.
4. Wait for your paired device to become reachable, select it and tap **Connect**.
5. Confirm fresh screenshots and input readiness before arming a demo.

The demo uses bundle ID `com.raynan.celluse`. Pair it after installation.

Disconnect USB and stop any desktop control sessions before evaluating the
on-device execution claim. Keep the phone unlocked. Follow [the demo steps](demo.md).

## Diagnose setup separately from actions

- **Offline/searching:** check local-network permission, VPN state, selected peer
  address, saved pairing and whether the phone is unlocked.
- **Developer image/service failure:** prepare compatible developer services.
- **Input not ready:** wait for a fresh portrait screenshot in the active session.
- **Background expired:** the OS ended the execution allowance; stop and start a
  new user-initiated run.

Use **View report** for typed diagnostics. Older experiment sections can show
false flags even when `agentRun.runner.inputs` records a successful generic run.
