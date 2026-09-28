# Contributing

Start with an issue describing the use case, device/OS, expected behavior and a
redacted report. Do not upload pairing records, signing material, account details,
screenshots of private apps or model API keys.

Run `swift test` for the portable CellUse package. On Linux,
`swift test --package-path Runtime` tests the reference app's pure core. On macOS,
`bash Scripts/build-macos.sh` bootstraps the transport, compiles the iPhone app
and runs the core, routing, media and runtime integration tests.

For the optional embedded connection, `swift test` includes the packet-routing
suite. Run `bash Scripts/build-embedded-tunnel.sh` on Mac to compile and inspect
the standalone host and its embedded extension, without bootstrapping DeviceHub.

Keep perception/model policy separate from input transport. Preserve observation
binding, cancellation and uncertain-delivery behavior. Never automatically retry
an input whose delivery status is unknown. State whether a result is mocked,
transport-acknowledged, visually checked by a person, or model-verified.

Native patch changes must regenerate and verify the hashes in `dependencies.json`.
Keep model/perception experiments separate from the core transport test suite.

By submitting original contributions, you agree to license them under the
repository's Apache-2.0 license. Preserve upstream attribution for derived work.
