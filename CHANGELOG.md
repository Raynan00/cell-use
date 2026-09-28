# Changelog

## 0.1.0-alpha.2

- Optional `CellUseTunnel` SwiftPM product with an embedded packet-tunnel provider
  and host connection controller.
- App-extension template, signing entitlements and standalone iOS host example
  for developers bundling the connection inside their own apps.
- IPv4 route validation, packet checksum/payload tests and unsigned iOS
  app/extension build checks.

## 0.1.0-alpha.1

Initial developer preview, derived from Phone Probe build 20.

- Root `CellUse` Swift package: observation/action protocol, ordered runner,
  bounded input delivery, replay/freshness checks and redacted diagnostics.
- Separate `CellUseRuntime` Apple adapter with native session ownership checks,
  cancellation, screenshots and tap/swipe/US-ASCII input.
- Reference iOS app branded cell-use (build 21), including local VPN routing,
  pairing, ordinary/continued background work and scripted experiments.
- Pinned, checksum-verified DeviceHub/idevice transport patches and build scripts.
- Apache-2.0 original source, retained upstream notices, setup and integration docs.
