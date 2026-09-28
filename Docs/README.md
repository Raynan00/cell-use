# cell-use documentation

cell-use is an open-source Swift SDK for on-device iPhone automation. It provides
screenshots and phone actions for AI agents, an iOS runtime and an optional local
tunnel that developers can embed in their own apps.

## Start here

- [iPhone demo setup](setup.md): signing, Developer Mode, pairing and connection.
- [Run the demos](demo.md): swipe in Settings, type in Notes and use Calculator.
- [Frequently asked questions](faq.md): architecture, models and app packaging.

## Build with cell-use

- [Swift API reference](api.md): `PhoneAgent`, observations, actions and the runner.
- [iOS runtime integration](runtime-integration.md): connect an agent to screen
  capture, input and the host app's background tasks.
- [Embedded tunnel](embedded-tunnel.md): include the connection in your app using
  `CellUseTunnel` and a packet-tunnel extension.
- [Extension template](../Templates/EmbeddedTunnel): provider class, Info.plist
  and signing entitlements.
- [Host example](../Examples/EmbeddedTunnelHost): buildable app and extension.

## Project

- [Source and overview](../README.md)
- [Changelog](../CHANGELOG.md)
- [Contributing](../CONTRIBUTING.md)
- [Release guide](releasing.md)
- [GitHub releases](https://github.com/Raynan00/cell-use/releases)
- [License](../LICENSE) and [dependency notices](../THIRD_PARTY_NOTICES.md)
