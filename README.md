# cell-use

**Let AI agents use your phone—from your phone.**

A Swift harness for screenshot-driven agents, with an iPhone runtime that
observes the screen and delivers taps, swipes and text to other apps on the
same phone. Bring your own agent or model.

The execution host is the iPhone. Setup includes signing, Developer Mode,
pairing, developer-service preparation and a local VPN.

## What you get

| Component | Purpose | Installation |
| --- | --- | --- |
| **CellUse** | Agent protocol, actions, ordered runner and diagnostics | SwiftPM URL + version |
| **CellUseRuntime** | iPhone screenshot and input adapter | Clone and build with native dependencies |
| **CellUseTunnel** | Embedded local connection for your own app | SwiftPM product + packet-tunnel extension target |
| **cell-use demo** | Reference app for pairing, background tasks and device experiments | Sign the release IPA, or build with Xcode |

Use the portable SDK to implement your agent, and the native runtime to connect
it to an iPhone. The reference app supplies the session and background-task setup.

Building your own app? [Embed the tunnel](Docs/embedded-tunnel.md) to ship the
connection inside your app, with no separate LocalDevVPN installation. The
publishing developer signs the app and extension; users need no paid developer
account. This component is available on `main` ahead of its first versioned release.

## Install the agent SDK

Add `https://github.com/Raynan00/cell-use` in Xcode's package dependencies, selecting
the exact version `0.1.0-alpha.1` and the **CellUse** product. Or use SwiftPM:

```swift
dependencies: [
    .package(url: "https://github.com/Raynan00/cell-use.git", exact: "0.1.0-alpha.1")
]
// In your target's dependencies:
// .product(name: "CellUse", package: "cell-use")
```

Implement the provider interface:

```swift
import CellUse

struct MyAgent: PhoneAgent {
    let choose: @Sendable (PhoneObservation) async throws -> PhoneAction

    func nextAction(for observation: PhoneObservation) async throws -> PhoneDecision {
        let action = try await choose(observation)
        return PhoneDecision(observation: observation, action: action)
    }
}
```

Pass `observation.screenshotPNG` to your chosen model and return an action.
Every decision is bound to one run and one observation. The runner handles
sequencing, freshness checks, cancellation and input delivery diagnostics.

Actions: **tap · swipe · typeText · wait · finish**.

Read the [API](Docs/api.md), [native integration](Docs/runtime-integration.md)
and [iPhone setup](Docs/setup.md).

## Try it on an iPhone

1. Follow [setup](Docs/setup.md) to prepare developer services, sign the app,
   enable Developer Mode, start LocalDevVPN and pair the phone.
2. Use **Connect** and **Arm swipe test** with Settings, or **Arm text test**
   with an empty Notes draft. Switch to the target app and leave it untouched.
3. Return to cell-use and inspect the final image and run report.

The included scripted clients make it easy to try the action loop before
connecting your own model. The [demo guide](Docs/demo.md) also covers ordered
Calculator taps (`0 → 7 → 77`) and background inputs after 60 seconds.

## Build and contribute

```sh
git clone https://github.com/Raynan00/cell-use.git
cd cell-use
swift test                         # portable SDK; Swift 6+
swift test --package-path Runtime  # core on Linux; native tests after bootstrap on Mac
```

For the iPhone app, use macOS with Xcode 27, Python 3, Rust/rustup, XcodeGen and
ripgrep, then run `bash Scripts/build-macos.sh`. The script prepares pinned native
dependencies, builds the unsigned app and runs the SDK and native integration
suites. Windows users can sign a release IPA.

See [contributing](CONTRIBUTING.md) and [release procedure](Docs/releasing.md).

## License and acknowledgements

Cell-use's original code is **Apache-2.0**, copyright Raynan Wuyep and contributors.
The native transport builds on [DeviceHub iOS](https://github.com/JaviSoto/device-hub-ios)
and its patched [idevice](https://github.com/jkcoxson/idevice) dependency, under
their own MIT licenses. Our native patches retain those notices. We provide the
agent contract, runner, same-phone integration and reference app; the underlying
transport is upstream work. See [third-party notices](THIRD_PARTY_NOTICES.md).
