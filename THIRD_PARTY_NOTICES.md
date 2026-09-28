# Third-party components

cell-use uses Device Hub iOS, copyright its contributors, under its MIT license:
https://github.com/JaviSoto/device-hub-ios/tree/1fcdfb0a6799b62f05625d0cbb359bec57256b94

The dependency is fetched at an immutable revision. Its unmodified LICENSE,
Licenses directory, and transitive notices are preserved in that checkout; the
app bundles that license as DeviceHub-MIT.txt and its Licenses directory. A copy
of the pinned upstream license is also in this repository's Licenses directory.
Device Hub includes a patched
MIT-licensed idevice library, copyright Jackson Coxson and contributors.

Build 7 applies the checksum-pinned `Patches/devicehub-media-diagnostics.patch`
to three upstream Swift files. Build 8 extends it with an explicit software-only
decoder selection and actual hardware-decoder queries. The bounded media-failure
recorder remains. Decoder recovery and authentication are unchanged. Source and resulting-file hashes
are verified by our bootstrap script; upstream license files remain unchanged.
Build 9 additionally patches the Swift native factory/marshaller, the matching
C/Rust operation enum, native request validation, and protocol dispatch to add
a bounded PNG screenshot experiment. The patch now covers nine files. It leaves
existing screenshot/video operations and authentication intact. The reproducible
patch generator is `Scripts/generate-probe-patch.py`.
Build 10 extends the PNG operation with authenticated tap input and owned input
cleanup, using the upstream HID implementation. It adds a worker-lifecycle patch
and now covers ten upstream files. `Patches/png-input-loop.rs` is the source
fragment used by the generator. Existing video sessions retain their behavior.

No StikPair or StikDebug source is incorporated. Their documentation informed
the feasibility investigation. There is no claimed affiliation with Apple or
the upstream projects.

The public alpha preserves the build 20 native patch, including swipe, keyboard
and release-all input in the PNG session. Historical "Phone Probe" comments in
that checksum-pinned patch refer to the development prototype of cell-use.
The Apache-2.0 license for our original code does not replace dependency licenses.
