# Release procedure

Release the portable Swift package by a semantic version tag on this repository.
There is no npm/PyPI upload: this is a Swift library, not a JavaScript/Python wrapper.
The first version is `0.1.0-alpha.1`; prerelease APIs may change.

1. Run `swift test`, the Linux core suite and bootstrap integrity tests.
2. Run the manual **Validate cell-use** workflow. Require a passing iPhone build
   and the supported Apple integration suites before attaching its unsigned IPA.
3. Confirm the artifact bundle/version, arm64 device executable and required
   license files. Never upload a personalized/signed archive, provisioning profile,
   pairing record or developer image.
4. Tag the exact validated source as `0.1.0-alpha.1` (update for later releases).
5. Create a GitHub prerelease with the unsigned IPA, `SHA256SUMS` and `build-info.json`.
   State the source revision, CI run and package changes.
6. Resolve and build an external SwiftPM consumer against the public tag.

Build metadata must distinguish app build number, package version, agent contract
version and native dependency revision. The pure Swift package source is covered
by Apache-2.0; native dependencies keep their own licenses. GitHub automatically
provides tagged source archives.

For a package/template-only release, run the **Validate embedded tunnel** workflow
when that component changes. It compiles the iOS host and extension and checks
the embedded bundle. Publish the tagged sources and release notes without a new
full-demo IPA when the phone runtime/demo is unchanged; keep its existing release
link. An unsigned build check does not replace signed physical-device validation.
