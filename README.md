# cell-use

**On-device iPhone automation for AI agents.**

cell-use is an open-source Swift SDK for building agents that control iOS apps
from the iPhone itself. Capture screenshots, tap, swipe and type through a common
API. Connect your own model to decide what happens next.

[Documentation](Docs/README.md) · [Swift API](Docs/api.md) · [Embed in your app](Docs/embedded-tunnel.md) · [Releases](https://github.com/Raynan00/cell-use/releases)

## iPhone control from your app

The phone runs the screenshot and input loop. Each step gives your agent a fresh
screenshot; the agent returns an action, and cell-use delivers it to the active
app. Use it to build mobile assistants, prototype iOS workflows or add phone
control to an existing Swift agent.

- **Screen capture:** PNG screenshots for your agent's vision model.
- **Phone actions:** tap, swipe, type text, wait and finish.
- **Multi-step execution:** run actions in order, with screenshots between steps.
- **Model integration:** implement `PhoneAgent` with your own decision logic.
- **Embedded connection:** bundle the local tunnel inside your app so users do
  not need a separate LocalDevVPN installation.

The native runtime uses Developer Mode, pairing, prepared developer services and
a local tunnel. Follow [iPhone setup](Docs/setup.md) for the demo or
[app integration](Docs/runtime-integration.md) for your own host.

## Swift packages

| Component | Purpose | Installation |
| --- | --- | --- |
| **CellUse** | Agent API, actions and execution loop | Swift Package Manager |
| **CellUseRuntime** | iPhone screenshot and input adapter | Clone and build with native dependencies |
| **CellUseTunnel** | Embedded local connection for your own app | SwiftPM product + packet-tunnel extension target |
| **cell-use demo** | Reference app for pairing, background tasks and device experiments | Sign the release IPA, or build with Xcode |

Use the portable SDK to implement your agent, and the native runtime to connect
it to an iPhone. The reference app supplies the session and background-task setup.

Building your own app? [Embed the tunnel](Docs/embedded-tunnel.md) to ship the
connection inside your app, with no separate LocalDevVPN installation. The
publishing developer signs the app and extension; users need no paid developer
account. See the host example for app/extension packaging and signing.

## Install with Swift Package Manager

Add `https://github.com/Raynan00/cell-use` in Xcode's package dependencies, selecting
the exact version `0.1.0-alpha.2` and the **CellUse** product. Or use SwiftPM:

```swift
dependencies: [
    .package(url: "https://github.com/Raynan00/cell-use.git", exact: "0.1.0-alpha.2")
]
// In your target's dependencies:
// .product(name: "CellUse", package: "cell-use")
```

Implement `PhoneAgent` to choose actions:

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

Pass `observation.screenshotPNG` to your model and return an action. The runner
handles action order, screenshot timing, cancellation and command results.

Actions: **tap · swipe · typeText · wait · finish**.

Read the [API](Docs/api.md), [native integration](Docs/runtime-integration.md)
and [iPhone setup](Docs/setup.md).

## Try the iPhone demo

1. Follow [setup](Docs/setup.md) to prepare developer services, sign the app,
   enable Developer Mode, start LocalDevVPN and pair the phone.
2. Use **Connect** and **Arm swipe test** with Settings, or **Arm text test**
   with an empty Notes draft. Switch to the target app and leave it untouched.
3. Return to cell-use and inspect the final image and run report.

The included scripted clients make it easy to try the action loop before
connecting your own model. The [demo guide](Docs/demo.md) also covers ordered
Calculator taps (`0 → 7 → 77`) and background inputs after 60 seconds.

The full-control demo IPA is available in
[0.1.0-alpha.1](https://github.com/Raynan00/cell-use/releases/tag/0.1.0-alpha.1).
The SDK and embedded tunnel templates are available in
[0.1.0-alpha.2](https://github.com/Raynan00/cell-use/releases/tag/0.1.0-alpha.2).

## Common questions

**Does cell-use need a computer while an agent runs?**
The native control loop runs on the iPhone. Initial signing and developer-service
preparation are described in the [setup guide](Docs/setup.md).

**Can I use an on-device model or a cloud model?**
Yes. Implement `PhoneAgent` with either. Your provider determines where inference
runs and whether screenshots leave the phone.

**Is cell-use an app or a library?**
It is a developer library with an iPhone runtime, an optional embedded tunnel and
example apps. You build and distribute your own app around it.

**Which iOS version does it target?**
The current native phone-control runtime targets iOS 27. The portable Swift API
and tunnel component declare iOS 17 as their minimum version.

Read the [FAQ](Docs/faq.md) for integration, signing and model setup.

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

## License and credits

Created by [Raynan Wuyep](https://github.com/Raynan00). Original cell-use code is
licensed under [Apache-2.0](LICENSE).

The native transport uses [DeviceHub iOS](https://github.com/JaviSoto/device-hub-ios)
and its patched [idevice](https://github.com/jkcoxson/idevice) dependency under
MIT licenses. See [third-party notices](THIRD_PARTY_NOTICES.md).
