# Embed the connection in your app

Ship your app, agent, cell-use runtime and local tunnel in one installation.
`CellUseTunnel` provides the host controller and packet-tunnel provider. The
extension is bundled inside your app; users do not install LocalDevVPN.

## Add the package and extension

Add this repository at version `0.1.0-alpha.2` and select the `CellUseTunnel`
product for both your iOS app and a **Network Extension / Packet Tunnel** target. The tunnel component targets
iOS 17+; the current phone-control runtime targets iOS 27.

1. Give the extension an identifier below your app's identifier, for example
   `com.example.myagent.tunnel` for `com.example.myagent`.
2. Add the files in [Templates/EmbeddedTunnel](../Templates/EmbeddedTunnel) to
   your project. `PacketTunnelProvider.swift` and `Info.plist` belong to the
   extension target. The principal-class entry must remain
   `$(PRODUCT_MODULE_NAME).PacketTunnelProvider`.
3. Enable **Network Extensions → Packet Tunnel** for the app and extension.
   Merge the supplied `Host.entitlements` and `Tunnel.entitlements` into their
   respective entitlement files; preserve your existing entitlements.
4. Select the same Apple Developer Program team for both targets, with matching
   provisioning profiles. The publishing developer needs paid signing for this
   capability; users do not need their own developer membership.
5. Embed the extension in the host's **Embed App Extensions** build phase.
   App Groups are not required: configuration is passed through the VPN profile.

The host uses `NETunnelProviderManager` for the custom packet tunnel; it does not
require the separate Personal VPN entitlement used for built-in IKEv2/IPsec.
See Apple's [Network Extension configuration](https://developer.apple.com/documentation/xcode/configuring-network-extensions/).

## Start from your host app

Retain a controller for the lifetime of your connection:

```swift
import CellUseTunnel

// On MainActor, e.g. as a property of your host coordinator:
let tunnel = CellUseTunnelController(
    providerBundleIdentifier: "com.example.myagent.tunnel"
)

// From an explicit user Connect action:
try await tunnel.connect()
// Now pair/open the native runtime through 10.7.0.1, using port 49152
// for the initial developer-service endpoint in the tested configuration.

// On explicit user Disconnect (close the native session first):
tunnel.disconnect()
```

iOS asks the user to approve the VPN configuration. `connect()` reloads the saved
profile, starts its provider, and waits up to 15 seconds for the connected state
after profile setup. It touches only the matching provider's profile. Use one
controller for that identifier and read its `status` when updating your UI.
Concurrent `connect()` calls on the same controller are rejected.

Tunnel readiness and developer-service readiness are separate: after connection,
perform the native route check, authenticated pairing and session creation shown
in [runtime integration](runtime-integration.md). Keep Developer Mode and
developer-service preparation in your onboarding. The extension supplies routing;
the host supplies the agent and its OS background-task lifecycle.

## Routing

Defaults match the tested external-tunnel setup:

| Setting | Address |
| --- | --- |
| Tunnel interface | `10.7.1.1/32` |
| Developer-service peer | `10.7.0.1/32` |

Only traffic for that peer is included. The provider reflects IPv4 TCP/UDP
packets between the configured addresses on the same phone, preserving transport
checksums and payloads. It sets no DNS servers, IPv6 route or remote VPN server.
Malformed packets and packets for other addresses are discarded.

To use different addresses, pass two distinct private IPv4 addresses without
subnet suffixes. Stop the connection before changing them:

```swift
let configuration = try TunnelConfiguration(
    interfaceAddress: "10.7.1.1", deviceAddress: "10.7.0.1"
)
try await tunnel.connect(configuration: configuration, displayName: "My Agent")
```

## Build the host example

The [EmbeddedTunnelHost example](../Examples/EmbeddedTunnelHost) demonstrates the
complete app/extension packaging independently of the native control dependency.
From a clone of this repository on a Mac with Xcode and XcodeGen:

```sh
bash Scripts/build-embedded-tunnel.sh
open Examples/EmbeddedTunnelHost/EmbeddedTunnelHost.xcodeproj
```

Set `CELL_USE_BUNDLE_ID` to your app's identifier and select your paid signing team
for both targets. The extension identifier follows the host automatically. Build
and run on a physical iPhone, approve the VPN prompt and check **Connect**.
The example exposes the tunnel; add `CellUseRuntime` and your agent for phone
control. It is not a replacement for the full scripted-control demo.

For the first device check, disable any external local VPN, start the embedded
tunnel, then verify pairing, screenshots and input through your native session.
Test stopping and reconnecting as well. The existing release demo still supports
free-account signing with an external local tunnel; see [demo setup](setup.md).
