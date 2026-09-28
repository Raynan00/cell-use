# CellUse

A standalone Swift 6 package for coordinating screenshot-driven phone actions.
It has no model, networking, UIKit, DeviceHub or external package dependencies.
`PhoneAgent` chooses actions; `PhoneActionRunner` owns sequencing and evidence;
a platform adapter captures images and delivers commands. The separate `Runtime` package exports `CellUseRuntime`, the Apple adapter used by the demo. See [runtime integration](runtime-integration.md).
The coordinator alone does not control a phone.

## Provider interface

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

`PhoneObservation` contains a unique frame ID, run ID, portrait image dimensions,
monotonic capture time, PNG bytes, a zero-based decision index and accepted-tap
count. The image bytes are supplied to the provider. Runner diagnostic snapshots
record their byte count, never the image contents. Providers are responsible for
how they use the image; the included client keeps it local and performs no I/O.

Supported actions:

- `.tap(x:y:)`: normalized full-image coordinates in `[0, 1)`, origin top-left.
  The adapter maps them to the supplied image's pixel dimensions.
- `.swipe(fromX:fromY:toX:toY:duration:)`: normalized endpoints, 0.2...1 seconds.
  Twelve paced move/release updates follow touch-down.
- `.typeText(_:)`: 1...32 printable US-ASCII characters using HID key taps.
  The entire string is validated before input. Requires an English (US) keyboard
  layout and an already focused editable field. No Unicode, paste or implicit Return.
- `.wait(seconds:)`: a finite interval from 0.1 through 5 seconds, followed by
  a new observation before the next decision.
- `.finish`: end the run. This is the provider's completion request, not an
  assertion that the user's task was semantically achieved.

The decision includes version 1 and echoes the exact run ID and observation ID.
All request/response types are Codable and Sendable. Data uses Foundation's
base64 JSON representation. This is a versioned data contract and in-process
protocol; no HTTP/MCP server or external model provider is installed by this SDK.

A deterministic client is included:

```swift
let agent = ScriptedPhoneAgent(actions: [
    .tap(x: 0.2, y: 0.6),
    .wait(seconds: 1),
    .tap(x: 0.2, y: 0.6),
    .finish
])
```

Each decision is requested from a new screenshot. The scripted client indexes
this list with decisionIndex and does not interpret image contents.

## Platform adapter obligations

1. Construct a coordinator for one run, then call start with monotonic time.
2. Feed session-scoped metadata via offer. Only encode and send an observation
   when it returns true. Frames must be fresh, portrait, input-ready and retain
   consistent dimensions. Two distinct eligible frames are required by default.
3. Invoke the agent asynchronously, continuing frame reception and watchdog ticks.
   Pass its reply to resolve. Only a returned InputCommand permits native input.
4. Recheck live input readiness and latest frame freshness/geometry before
   delivering the reply. Acknowledge the exact command ID only when transport
   returns. An error or delivery timeout is uncertain and must not be retried.
5. Cancel the provider task and stop the coordinator on foreground return,
   session replacement, transport termination or cancellation. Ignore late replies.
   Check cancellation immediately before delivery and after each awaited operation.
6. Call tick independently of frame/decision arrival, including while waiting
   for a provider. The app adapter ticks every 250 ms and disconnects on termination.

The runner consumes each observation once and permits only one in-flight command.
After acceptance, eligible frames must be captured at least one second later.
Stale or wrong-run/observation replies cannot produce commands. The adapter's
watchdog also stops runs when the provider never responds; cancellation is
cooperative, so a noncooperative provider may keep computing, but its late reply
cannot authorize input after the run stops.

Default limits: 22 seconds total, 5 seconds for a decision, 5 seconds for delivery,
8 seconds for fresh frames after their eligibility time, 8 taps, 16 total inputs and 16 decisions.
Initial background delay is 3 seconds. Fresh incoming frames may be at most
2 seconds old; a decision's source frame may be at most 5 seconds old. The
Configuration values can be adjusted for another host's tested execution budget.
The OS may still terminate an app independently; these limits do not grant
background execution or prevent suspension.

## Testing

```sh
swift test
```

The package has no external dependencies. Tests cover observation binding,
ordered inputs, waits, deadlines, cancellation, validation and diagnostics.
The input API advertises `tap`, `swipe`, `typeText`, `wait` and `finish`.
Providers should emit capabilities advertised by their host.
