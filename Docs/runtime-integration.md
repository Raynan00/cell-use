# iPhone runtime integration

`CellUse` provides the agent contract and coordinator. `CellUseRuntime` connects
them to an authenticated iPhone session. The reference app shows how to provide
pairing, local VPN routing and background-task lifecycle management.

## Packaging

The root Swift package provides `CellUse`, the portable agent API and runner.
The `Runtime` package provides `CellUseRuntime`, the Apple session adapter.
After cloning this repository, run `bash Scripts/build-macos.sh` on macOS with
Xcode 27. This bootstraps the pinned native dependencies and generates the
`CellUseDemo.xcodeproj` reference app. See [setup](setup.md).

For your own iOS host, add the `Runtime` directory as a local Swift package and
select its `CellUseRuntime` product. The reference `project.yml` also shows the
required DeviceHubLive, private-media and native-framework targets. Use this source build for native iPhone control.

## Host ownership

The host creates and owns the authenticated DeviceSession, LocalDevVPN route,
pairing records, developer-service preparation, discovery, event/frame streams,
and OS background task. The runtime takes a session and an agent; it does not
create a connection, claim background time or bypass signing requirements.

```swift
import CellUse
import CellUseRuntime

// session is the host's existing DeviceSession; retain runtime for the run.
let runtime = CellUseRuntime(runID: runID, session: session, agent: agent)
runtime.onUpdate = { snapshot in /* display/store redacted diagnostics */ }
runtime.onObservation = { frame, snapshot in /* optional local evidence */ }
runtime.onEnded = { /* finish work and close the owned session */ }
runtime.start() // when the host's approved execution window begins

// From the host's single frame/event consumer:
runtime.receive(frame, inputReady: inputReady)
runtime.updateInputReadiness(inputReady)

// On foreground return, user stop, background expiration or session replacement:
runtime.cancel("hostStopped")
```

All runtime APIs/callbacks run on MainActor. Keep event and frame reception alive
while the provider/delivery tasks await. Do not make a second competing consumer
of the same frame stream. Cancel before replacing a session; close it on end.
Callbacks should capture their host weakly. For extended processing, the host
must separately register/start its OS task and report real completed work. The
working probe demonstrates 60-image plus four-decision progress accounting.

## Input contract

Tap, swipe and text use the same single-use observation binding, fresh portrait
frame gates, action budget, watchdog and terminal uncertain-delivery behavior.
Swipe accepts normalized endpoints and 0.2...1-second duration. Text accepts
1...32 printable US-ASCII characters, with no Return, using the US HID layout.
The host/user must focus the intended text field and keep portrait orientation
locked. App identity and field focus are not inferred by this transport.

Every gesture edge/key checks cancellation and live input context. Invalid text
is rejected before its first character. After a partial failure, the adapter
attempts release-all and stops; it never resends the string or gesture. Session
teardown provides native cleanup as well. A transport return only means queue
acceptance; a later screenshot and the agent/user determine what actually happened.

Decisions and observations carry private text/screenshots. Runner snapshots
record kinds, IDs, counts and timings, never those payloads. Hosts/providers own
their retention and network policies. The supplied scripted client makes no
network/model calls.

The native capture session uses portrait screenshots and a 120-second session
budget. Configure the runner to fit the host's granted background execution
window, and handle cancellation through the lifecycle callbacks above.
