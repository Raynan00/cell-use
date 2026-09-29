# cell-use FAQ

## What is cell-use?

cell-use is an open-source Swift SDK for on-device iPhone automation. Developers
use it to give AI agents screenshots and controls for other iOS apps. The API
supports taps, swipes, text input, waits and completion. The native control loop
runs on the same iPhone as the target app.

## How does an agent use the phone?

The runtime captures a screenshot and passes it to your `PhoneAgent` provider.
Your provider returns a `PhoneDecision` containing the next action. The runner
checks that the decision belongs to the current screenshot and run, delivers the
input, then captures another screenshot for the next step.

See the [Swift API](api.md) and [runtime integration](runtime-integration.md).

## Where does the AI model run?

You choose. `PhoneAgent` is a Swift interface, so its implementation can call an
on-device model, a hosted vision model or your own service. cell-use does not
choose or include a model. The supplied demos use scripted action sequences.

The phone-control runtime runs on the iPhone regardless of where your provider
performs inference. Your provider decides whether to send screenshots off-device.

## Can I build an app with everything included?

Yes. Combine `CellUse`, `CellUseRuntime` and `CellUseTunnel` with your agent.
Include the supplied packet-tunnel extension in your app bundle. That packaging
removes the separate LocalDevVPN installation from your users' setup.

The [embedded tunnel guide](embedded-tunnel.md) covers the extension, host code
and signing. The developer signs the app and extension using an Apple Developer
Program team. Users do not need their own paid developer account.

## Why is there a local tunnel?

The native connection uses a local network route to reach developer services on
the same iPhone. `CellUseTunnel` supplies that route inside your app. The released
demo can also use an external local tunnel for free-account testing.

The embedded route stays on the phone and has no external VPN server. This is
separate from any network requests your model provider makes.

## Is a Mac or PC required during a run?

The native agent loop runs on the iPhone. A computer is used for initial signing,
installation and developer-service preparation. The full source build uses
macOS and Xcode; Windows users can sign the released demo IPA. Follow
[iPhone setup](setup.md) before running the examples.

## What do I install with Swift Package Manager?

The root package exports `CellUse` for the agent API and `CellUseTunnel` for the
embedded connection. `CellUseRuntime` is a separate source package that connects
the API to native iPhone services. It uses the pinned native dependencies prepared
by the build scripts.

Choose `CellUse` to write an agent. Follow [runtime integration](runtime-integration.md)
to control a phone, and [embedded tunnel setup](embedded-tunnel.md) to package the
connection inside your app.

## Why does the native runtime require iOS 27?

The minimum follows the supplied phone-control implementation. `Runtime/Package.swift`,
the reference app and the pinned DeviceHub Swift package target iOS 27. The
upstream native framework build and its verification script also specify 27.0.
Apple documents the Device Hub nearby-device pairing flow used here for
iOS 27 and later in the [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

The root Swift package declares iOS 17 for the independent `CellUse` agent API
and `CellUseTunnel` network route. Those components do not supply the native
screenshot and input services on their own. Lowering the app's deployment target
does not change the dependency or the services available on the phone.

Supporting an earlier iOS release would require a compatible screenshot/input
transport and pairing route, along with matching builds and device verification.
The agent API can accommodate another adapter without changing the provider's
decision interface.

## Is extended background processing the reason for iOS 27?

No. Apple introduced `BGContinuedProcessingTask` in iOS 26; see
[Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/).
Background execution and native phone control have separate requirements.
The current runtime's iOS 27 minimum applies to both ordinary and extended runs.

## Does embedding the tunnel remove the other setup steps?

It removes the separate LocalDevVPN installation. The native transport still
uses Developer Mode, saved pairing and prepared developer services. See
[setup](setup.md#requirements) for initial preparation and run-time requirements.

## What should I try first?

The [scripted demos](demo.md) cover a Settings swipe, typing into a Notes draft
and two Calculator taps that change `0` to `7` and then `77`. They show the action
loop before you connect a model.

## What is the license?

Original cell-use code is licensed under [Apache-2.0](../LICENSE). The native
transport uses DeviceHub iOS and idevice under their own MIT licenses. See the
[dependency notices](../THIRD_PARTY_NOTICES.md).
